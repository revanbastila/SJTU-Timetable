package cn.sjtu.jiaotong_course

import android.app.*
import android.app.job.*
import android.content.*
import android.os.*
import android.Manifest
import android.content.pm.PackageManager
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Log
import android.util.Base64
import android.webkit.CookieManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.security.KeyStore
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.spec.GCMParameterSpec

/** Tokens remain app-private and encrypted with an Android Keystore AES key.
 * Never use the reference project's debug token, captcha solver or teacher QR APIs. */
private object AttendanceSecrets {
    private const val ALIAS = "attendance_session_v1"
    private fun key(): java.security.Key {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        store.getKey(ALIAS, null)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    fun seal(value: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        return Base64.encodeToString(cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
    }
    fun open(value: String): String {
        val bytes = Base64.decode(value, Base64.NO_WRAP)
        require(bytes.size > 28)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0,12)))
        return String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8)
    }
}

object AttendanceSync {
    const val EXTRA_PENDING = "attendance_pending"
    private const val PREFS = "attendance_v1"
    private const val JOB = 4127
    private const val HOST = "mlearning.sjtu.edu.cn"
    private const val BASE = "https://$HOST/lms-lti-rollcall-sjtu"
    private val work = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val revision = AtomicInteger()
    private val recordLock = Any()
    private val automaticReads = java.util.concurrent.ConcurrentHashMap<String,Pair<Long,JSONObject>>()
    private var channel: MethodChannel? = null
    @Volatile private var appForeground = false
    private val activeRequests = java.util.Collections.synchronizedSet(mutableSetOf<HttpURLConnection>())
    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private class ReadFailure(val reason: String) : Exception()

    fun bind(activity: MainActivity, messenger: BinaryMessenger, frame: AttendanceFrameCapture) {
        channel = MethodChannel(messenger, "cn.sjtu.jiaotong_course/attendance")
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "configure" -> {
                    try {
                        val p = prefs(activity)
                        appForeground = call.argument<Boolean>("foreground") == true
                        val account = call.argument<String>("account") ?: ""
                        synchronized(recordLock) {
                            if (p.getString("account", "") != account) p.edit().clear().commit()
                            val enabled = call.argument<Boolean>("enabled") == true && account.isNotBlank()
                            val windows = JSONArray(call.argument<List<Map<String, Any?>>>("meetings") ?: emptyList<Any>())
                            p.edit().putString("account", account).putBoolean("enabled", enabled)
                                .putString("windows", windows.toString()).commit()
                            revision.incrementAndGet()
                            val scheduler = activity.getSystemService(JobScheduler::class.java)
                            if (!enabled || windows.length() == 0) scheduler.cancel(JOB)
                            else if (scheduler.getPendingJob(JOB) == null) scheduler.schedule(
                                JobInfo.Builder(JOB, ComponentName(activity, AttendanceJobService::class.java))
                                    .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                                    .setPeriodic(15 * 60_000L, 5 * 60_000L).setPersisted(true).build())
                            if (!enabled) { frame.cancel(); cancelNotifications(activity); p.edit().putString("record_queue_v2","{}").commit() }
                        }
                        AttendanceMonitor.schedule(activity, appForeground)
                        result.success(null)
                    } catch (_: Exception) { result.error("attendance_config", "后台任务配置失败", null) }
                }
                "recordForeground" -> { foreground(activity, call.arguments == true); result.success(null) }
                "monitorStatus" -> result.success(AttendanceMonitor.status(activity))
                "exactAlarmSettings" -> {
                    if (Build.VERSION.SDK_INT >= 31) activity.startActivity(Intent(android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, android.net.Uri.parse("package:${activity.packageName}")))
                    result.success(null)
                }
                "cancel" -> {
                    revision.incrementAndGet()
                    synchronized(activeRequests) { activeRequests.toList().forEach { it.disconnect() } }
                    frame.cancel(); cancelNotifications(activity); result.success(null)
                }
                "notificationPermission" -> activity.requestAttendanceNotificationPermission(result)
                "notificationSettings" -> {
                    activity.startActivity(Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, activity.packageName))
                    result.success(null)
                }
                "installLtiNavigation" -> frame.installNavigation(call,result)
                "releaseWeb" -> frame.release(call,result)
                // Discovery/reminders only: no video capture or sign submission.
                "captureQr" -> frame.capture(call,result)
                "submit", "verify", "poll" -> result.success(mapOf("status" to "unsupported"))
                "connect" -> {
                    try {
                        val id = call.argument<String>("courseId") ?: ""
                        val code = call.argument<String>("courseCode") ?: ""
                        val token = call.argument<String>("token") ?: ""
                        require(id.matches(Regex("[0-9]+")) && code.matches(Regex("[A-Za-z0-9._~-]{1,128}")))
                        require(token.length in 16..16384 && !token.contains('\n') && !token.contains('\r'))
                        prefs(activity).edit().putString("connection_$id", JSONObject()
                            .put("courseCode", code).put("sealed", AttendanceSecrets.seal(token)).toString()).remove("bootstrap_next_$id").remove("bootstrap_reason_$id").commit()
                        result.success(null)
                    } catch (_: Exception) { result.error("attendance_session", "无法保存签到系统登录状态", null) }
                }
                "claimRecord" -> {
                    val id = call.argument<String>("courseId") ?: ""
                    val key = call.argument<String>("recordKey") ?: ""
                    result.success(claim(activity,id,key,call.argument<Boolean>("foreground") == true))
                }
                "ackRecord" -> {
                    val key=call.argument<String>("recordKey") ?: ""
                    synchronized(recordLock) {
                        val queue=JSONObject(prefs(activity).getString("record_queue_v2","{}")!!)
                        queue.remove(key);prefs(activity).edit().putString("record_queue_v2",queue.toString()).commit()
                    }
                    activity.getSystemService(NotificationManager::class.java).cancel("attendance",key.hashCode())
                    result.success(null)
                }
                "notifyRecord" -> {
                    val id = call.argument<String>("courseId") ?: ""
                    val key = call.argument<String>("recordKey") ?: ""
                    val row = cachedRows(activity,id).firstOrNull { it.optString("key") == key }
                    if (row != null && isCurrent(activity,id,row)) {
                        synchronized(recordLock) {
                            val queue = JSONObject(prefs(activity).getString("record_queue_v2","{}")!!)
                            queue.put(key,true); prefs(activity).edit().putString("record_queue_v2",queue.toString()).commit()
                        }
                        notify(activity,key,call.argument<String>("name") ?: "课程")
                    }
                    result.success(null)
                }
                "notify", "acknowledge" -> result.success(null) // legacy channel, no submission.
                "tabs", "records", "submitRecord" -> {
                    val generation = revision.get()
                    val args = call.arguments as? Map<*, *> ?: emptyMap<Any,Any>()
                    work.execute {
                        val id = args["courseId"]?.toString() ?: ""
                        val response = try {
                            if (call.method == "tabs") tabs(id)
                            else if (call.method == "submitRecord") submitRecord(activity,id,JSONObject(args),generation)
                            else if (args["manual"] == true) inspect(activity,id,generation,args["name"]?.toString() ?: "课程")
                            else automaticInspect(activity,id,generation,args["name"]?.toString() ?: "课程")
                        } catch (e: ReadFailure) { failure(id,e.reason) }
                        catch (_: java.io.IOException) { failure(id,"network") }
                        catch (_: Exception) { failure(id,"format") }
                        main.post {
                            if (generation != revision.get()) result.error("cancelled", "操作已取消", null)
                            else result.success(jsonValue(response))
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    fun isForeground() = appForeground
    fun foreground(c: Context, value: Boolean) {
        appForeground=value
        if (value) prefs(c).edit().remove("monitor_quota").apply()
        AttendanceMonitor.schedule(c,value)
        if (!value) AttendanceMonitorService.kick()
    }
    fun nextAutomaticDelay(c: Context): Long {
        val now=SystemClock.elapsedRealtime()
        val generation=revision.get()
        return AttendanceMonitor.active(c).map {
            automaticReads["$generation:${it.optString("courseId")}"]?.first?.let { start -> (start+30_000-now).coerceAtLeast(1) } ?: 1L
        }.minOrNull() ?: 30_000L
    }
    fun timeChanged() { channel?.invokeMethod("timeChanged", null) }
    fun openPending() { channel?.invokeMethod("openPending", null) }
    private fun failure(id: String, reason: String): JSONObject {
        Log.i("AttendanceRecords","course=$id source=student_records time=${System.currentTimeMillis()} success=false reason=$reason")
        return JSONObject().put("status",reason).put("courseId",id).put("checkedAt",System.currentTimeMillis())
    }
    private fun request(url: String, token: String = "", deadline: Long = System.currentTimeMillis()+20_000): JSONObject {
        val target = URL(url)
        require(target.protocol == "https" && target.host in listOf(HOST, "oc.sjtu.edu.cn"))
        val c = target.openConnection() as HttpURLConnection
        activeRequests.add(c)
        try {
            val remaining = (deadline-System.currentTimeMillis()).coerceAtMost(10_000).toInt()
            if (remaining <= 0) throw java.net.SocketTimeoutException()
            c.instanceFollowRedirects = false
            c.connectTimeout = remaining; c.readTimeout = remaining
            c.useCaches = false
            c.setRequestProperty("Accept", "application/json")
            c.setRequestProperty("Cache-Control","no-cache, no-store")
            c.setRequestProperty("request-ajax","true")
            c.setRequestProperty("User-Agent", "SJTU-Timetable/1.14.27.3 Android")
            val cookies = CookieManager.getInstance().getCookie(url) ?: ""
            if (cookies.isNotBlank()) c.setRequestProperty("Cookie", cookies)
            if (target.host == HOST && token.isNotBlank()) c.setRequestProperty("Authorization", token)
            val status = c.responseCode
            if (status == 401 || status in 300..399) throw ReadFailure(if(target.host==HOST) "session_login" else "canvas_login")
            if (status == 403) throw ReadFailure("permission")
            if (status != 200) throw ReadFailure("server")
            val text = c.inputStream.use { input ->
                val out = java.io.ByteArrayOutputStream(); val buffer = ByteArray(8192)
                while (true) {
                    if (System.currentTimeMillis() >= deadline) throw java.net.SocketTimeoutException()
                    val count = input.read(buffer); if (count < 0) break
                    if (out.size()+count > 2_000_000) throw ReadFailure("format")
                    out.write(buffer,0,count)
                }
                out.toString("UTF-8")
            }
            if (text.trimStart().startsWith("<") && (text.contains("jaccount.sjtu.edu.cn") || text.contains("登录"))) {
                throw ReadFailure(if(target.host==HOST) "session_login" else "canvas_login")
            }
            return if (text.trimStart().startsWith("[")) JSONObject().put("tabs",JSONArray(text)) else JSONObject(text)
        } finally { activeRequests.remove(c); c.disconnect() }
    }
    private fun body(reply: JSONObject): Any? {
        if (reply.optString("code") == "401") throw ReadFailure("session_login")
        if (reply.optString("code") == "403") throw ReadFailure("permission")
        val code = reply.optString("resultCode")
        if (code in listOf("10001","10005")) throw ReadFailure("session_login")
        if (code != "200") throw ReadFailure("server")
        return reply.opt("body").takeUnless { it == JSONObject.NULL }
    }
    private fun connection(c: Context, id: String): Pair<String,String> {
        val p=prefs(c)
        val raw=p.getString("connection_$id",null)
        if(raw!=null) {
            try { val data=JSONObject(raw);return data.getString("courseCode") to AttendanceSecrets.open(data.getString("sealed")) }
            catch(_: Exception) { p.edit().remove("connection_$id").apply() }
        }
        val launch=tabs(id).optString("attendanceUrl")
        if(launch.isBlank()) throw ReadFailure("no_entry")
        val now=System.currentTimeMillis()
        if(now<p.getLong("bootstrap_next_$id",0)) throw ReadFailure(p.getString("bootstrap_reason_$id","connect_required") ?: "connect_required")
        val generation=revision.get()
        val session=AttendanceSessionResolver.resolve(c,launch) { generation==revision.get() }
        if(generation!=revision.get()) throw ReadFailure("cancelled")
        if(session.reason.isNotEmpty()) {
            p.edit().putLong("bootstrap_next_$id",now+5*60_000).putString("bootstrap_reason_$id",session.reason).apply()
            throw ReadFailure(session.reason)
        }
        p.edit().putString("connection_$id",JSONObject().put("courseCode",session.code)
            .put("sealed",AttendanceSecrets.seal(session.token)).toString()).remove("bootstrap_next_$id").remove("bootstrap_reason_$id").commit()
        Log.i("AttendanceRecords","course=$id source=canvas_lti session=connected")
        return session.code to session.token
    }
    private fun tabs(id: String): JSONObject {
        require(id.matches(Regex("[0-9]+")))
        val list = request("https://oc.sjtu.edu.cn/api/v1/courses/$id/tabs?per_page=100").getJSONArray("tabs")
        val out = JSONObject().put("status","ok")
        for (i in 0 until list.length()) {
            val row = list.optJSONObject(i) ?: continue
            if (row.optBoolean("hidden")) continue
            val label = row.optString("label").replace(Regex("[\\s（）()·]"), "")
            val uri = try { android.net.Uri.parse(URL(URL("https://oc.sjtu.edu.cn/"),row.optString("html_url")).toString()) }
                catch (_: Exception) { continue }
            if (uri.scheme != "https" || uri.host != "oc.sjtu.edu.cn" ||
                !uri.path.orEmpty().matches(Regex("/courses/$id/external_tools/[0-9]+"))) continue
            if (label == "点名签到") out.put("attendanceUrl",uri.toString())
            if (label.contains("课堂视频") && label.contains("新版") && !label.contains("旧版")) out.put("liveUrl",uri.toString())
        }
        return out
    }
    private fun parseDate(text: String): Long? {
        try { return java.time.OffsetDateTime.parse(text).toInstant().toEpochMilli() } catch (_: Exception) {}
        for (pattern in listOf("yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss")) {
            val f = java.text.SimpleDateFormat(pattern,java.util.Locale.ROOT).apply {
                isLenient=false; timeZone=java.util.TimeZone.getTimeZone("Asia/Shanghai") }
            val position = java.text.ParsePosition(0); val date=f.parse(text,position)
            if (date != null && position.index==text.length) return date.time
        }
        return null
    }
    private fun inspect(c: Context, id: String, generation: Int, name: String): JSONObject {
        if (generation != revision.get()) throw ReadFailure("cancelled")
        require(id.matches(Regex("[0-9]+")))
        val (code,token) = connection(c,id)
        val deadline = System.currentTimeMillis()+20_000
        val rows = linkedMapOf<String,JSONObject>(); var count=0; var invalid=0; var page=1
        do {
            if (generation != revision.get()) throw ReadFailure("cancelled")
            val data = try { body(request("$BASE/sign/records/?courseCode=${enc(code)}&pageNum=$page&pageSize=100",token,deadline)) }
                catch(e: ReadFailure) { if(e.reason=="session_login") prefs(c).edit().remove("connection_$id").apply();throw e } as? JSONObject
                ?: throw ReadFailure("format")
            val list = data.optJSONArray("dataList") ?: throw ReadFailure("format")
            for (i in 0 until list.length()) {
                count++
                val raw = list.optJSONObject(i)
                val created = raw?.optString("createdDate")?.let { parseDate(it) }
                if (raw == null || created == null || raw.optString("state").isBlank()) { invalid++;continue }
                val opaqueId = listOf("signHistoryId","id").firstOrNull { raw.has(it) && !raw.isNull(it) && raw.optString(it).isNotBlank() }
                val identity = if (opaqueId == null) "time:$created" else "$opaqueId:${raw.optString(opaqueId)}"
                val digest = java.security.MessageDigest.getInstance("SHA-256").digest(identity.toByteArray())
                    .joinToString("") { "%02x".format(it) }
                val key = "$id:$digest"
                rows[key] = JSONObject().put("key",key).put("createdAt",created).put("state",raw.getString("state"))
                    .put("availability","unknown") // Student list exposes no open/close field.
            }
            val total = data.optInt("total",count)
            if (count >= total) break
            if (page >= 20 || list.length()==0) throw ReadFailure("records_limit")
            page++
        } while (true)
        if (invalid>0 && rows.isEmpty()) throw ReadFailure("format")
        if (generation != revision.get()) throw ReadFailure("cancelled")
        val sorted = rows.values.sortedWith(compareByDescending<JSONObject> { it.getLong("createdAt") }.thenBy { it.getString("key") })
        val p = prefs(c)
        val known = p.getStringSet("observed_$id",emptySet()) ?: emptySet()
        val newCount = rows.keys.count { it !in known }
        synchronized(recordLock) {
            if (generation != revision.get()) throw ReadFailure("cancelled")
            p.edit().putStringSet("observed_$id",rows.keys.toSet()).putString("snapshot_$id",JSONArray(sorted).toString()).commit()
            val queue = JSONObject(p.getString("record_queue_v2","{}")!!)
            for (row in sorted) if (!isCurrent(c,id,row)) {
                queue.remove(row.getString("key"))
                c.getSystemService(NotificationManager::class.java).cancel("attendance",row.getString("key").hashCode())
            }
            p.edit().putString("record_queue_v2",queue.toString()).commit()
        }
        val latest = sorted.firstOrNull()
        val safeName=name.replace(Regex("[\\r\\n\\t]")," ").take(80)
        Log.i("AttendanceRecords","course=$id name=$safeName source=student_records time=${System.currentTimeMillis()} success=true records=${sorted.size} latest_at=${latest?.optLong("createdAt")} latest_state=${latest?.optString("state")} new_records=$newCount current_unsigned=${sorted.count { isCurrent(c,id,it) }} skipped=$invalid")
        return JSONObject().put("status","ok").put("courseId",id).put("checkedAt",System.currentTimeMillis())
            .put("records",JSONArray(sorted)).put("invalidRecords",invalid)
    }
    private fun submitRecord(c: Context,id: String,args: JSONObject,generation: Int): JSONObject {
        // Submission is only reached from the user's execution dialog while
        // that app-owned player is foreground. No poller calls this method.
        if (!appForeground || !prefs(c).getBoolean("enabled",false)) throw ReadFailure("cancelled")
        val (code,token)=connection(c,id)
        val qr=android.net.Uri.parse(args.getString("qr"))
        require(qr.scheme=="https" && qr.host==HOST && qr.port in listOf(-1,443) && qr.userInfo==null && qr.fragment==null &&
            qr.path in listOf("/lms/mobile2/forscan/","/lms/mobile2/forscan"))
        for(key in listOf("courseCode","signHistoryId","rollCallToken","fromType")) require(qr.getQueryParameters(key).size==1)
        if(qr.getQueryParameter("courseCode")!=code) throw ReadFailure("wrong_course")
        require(qr.getQueryParameter("fromType")=="scanRollCall")
        val task=qr.getQueryParameter("signHistoryId") ?: throw ReadFailure("unverified_task")
        val rollToken=qr.getQueryParameter("rollCallToken") ?: throw ReadFailure("unverified_task")
        require(task.matches(Regex("[A-Za-z0-9_-]{1,128}")) && rollToken.matches(Regex("[A-Za-z0-9._~-]{1,4096}")))
        inspect(c,id,generation,"课程")
        val row=cachedRows(c,id).singleOrNull { it.optString("key")==args.optString("recordKey") }
            ?: throw ReadFailure("unverified_task")
        if(!isCurrent(c,id,row)) throw ReadFailure("cancelled")
        // A student's row.id is NOT a signHistoryId, and rollcallNum is only an
        // ordinal. Require the official task response to bind id/course/time.
        // If student access or the contract does not expose this, fail closed.
        val metadata=try { body(request("$BASE/rollcall/${enc(task)}",token)) as? JSONObject }
            catch(_: Exception) { null }
        if(metadata==null || metadata.optString("id")!=task || metadata.optString("courseCode")!=code ||
            parseDate(metadata.optString("createdDate"))!=row.optLong("createdAt")) throw ReadFailure("unverified_task")
        if(generation!=revision.get() || !appForeground || !isCurrent(c,id,row)) throw ReadFailure("cancelled")
        val reply=request("$BASE/sign/scan/${enc(rollToken)}/${enc(task)}",token)
        Log.i("AttendanceRecords","course=$id source=qr_submit response_received=true")
        return JSONObject().put("status","ok").put("body",reply)
    }
    private fun automaticInspect(c: Context,id: String,generation: Int,name: String): JSONObject {
        // Serialized on work: foreground/background handover never starts a
        // second request for the same course in one 30-second slot.
        val now=android.os.SystemClock.elapsedRealtime()
        automaticReads["$generation:$id"]?.let { if(now-it.first in 0 until 30_000) return it.second }
        val response=try { inspect(c,id,generation,name) }
            catch(e: Exception) { failure(id,if(e is ReadFailure)e.reason else if(e is java.io.IOException)"network" else "format") }
        automaticReads.keys.removeAll { !it.startsWith("$generation:") }
        automaticReads["$generation:$id"]=now to response
        return response
    }
    private fun cachedRows(c: Context,id: String): List<JSONObject> {
        val rows = JSONArray(prefs(c).getString("snapshot_$id","[]"))
        return (0 until rows.length()).mapNotNull { rows.optJSONObject(it) }
    }
    private fun isCurrent(c: Context,id: String,row: JSONObject): Boolean {
        val p=prefs(c); if (!p.getBoolean("enabled",false) || row.optString("state")!="UNNORMAL") return false
        val now=System.currentTimeMillis(); val created=row.optLong("createdAt",Long.MIN_VALUE)
        val windows=JSONArray(p.getString("windows","[]"))
        return (0 until windows.length()).any {
            val w=windows.getJSONObject(it); val start=w.optLong("start"); val end=w.optLong("end")
            w.optString("courseId")==id && now>=start && now<end && created>=start && created<end && created<=now
        }
    }
    private fun claim(c: Context,id: String,key: String,foreground: Boolean): Boolean = synchronized(recordLock) {
        val row=cachedRows(c,id).firstOrNull { it.optString("key")==key } ?: return@synchronized false
        if (!isCurrent(c,id,row)) return@synchronized false
        val p=prefs(c); val seen=JSONArray(p.getString("record_seen_v2","[]"))
        val keys=(0 until seen.length()).map { seen.getString(it) }.toMutableList()
        val queue=JSONObject(p.getString("record_queue_v2","{}")!!)
        val fresh=key !in keys
        if (!fresh && !(foreground && queue.optBoolean(key))) return@synchronized false
        if (fresh) keys.add(key)
        if (foreground) queue.remove(key) else queue.put(key,true)
        while(keys.size>2000) queue.remove(keys.removeAt(0))
        p.edit().putString("record_seen_v2",JSONArray(keys).toString()).putString("record_queue_v2",queue.toString()).commit()
        Log.i("AttendanceRecords","course=$id reminder_claimed=true foreground=$foreground new=$fresh open=unknown")
        true
    }
    private fun enc(value: String) = URLEncoder.encode(value,"UTF-8")
    private fun jsonValue(value: Any?): Any? = when(value) {
        null, JSONObject.NULL -> null
        is JSONObject -> value.keys().asSequence().associateWith { jsonValue(value.get(it)) }
        is JSONArray -> (0 until value.length()).map { jsonValue(value.get(it)) }
        else -> value
    }
    fun background(c: Context, cancelled: () -> Boolean, monitor: Boolean = false, complete: () -> Unit) {
        val generation=revision.get()
        work.execute {
            try {
                val p=prefs(c)
                if (!monitor && AttendanceMonitorService.running) return@execute
                if (appForeground) { Log.i("AttendanceRecords","source=background skipped=foreground_owner"); return@execute }
                if (!p.getBoolean("enabled",false) || (!monitor && System.currentTimeMillis()<p.getLong("next",0))) return@execute
                val windows=JSONArray(p.getString("windows","[]")); val now=System.currentTimeMillis()
                val courses=mutableSetOf<String>(); var hadFailure=false
                for (i in 0 until windows.length()) {
                    if (cancelled() || generation!=revision.get()) return@execute
                    val w=windows.getJSONObject(i); val id=w.optString("courseId")
                    if (now<w.optLong("start") || now>=w.optLong("end") || !courses.add(id)) continue
                    try {
                        val read=automaticInspect(c,id,generation,w.optString("name","课程"))
                        if(read.optString("status")!="ok") { hadFailure=true;continue }
                    } catch (e: Exception) {
                        hadFailure=true
                        failure(id,if(e is ReadFailure) e.reason else if(e is java.io.IOException) "network" else "format")
                        continue
                    }
                    for (row in cachedRows(c,id)) {
                        if (cancelled() || generation!=revision.get()) return@execute
                        if (claim(c,id,row.getString("key"),false)) main.post {
                            if (!cancelled() && generation==revision.get() && isCurrent(c,id,row)) notify(c,row.getString("key"),w.optString("name","课程"))
                        }
                    }
                }
                p.edit().putLong("next",if(hadFailure) System.currentTimeMillis()+5*60_000 else 0).apply()
                main.post { channel?.invokeMethod("updated",null) }
            } catch (e: Exception) {
                val reason=if(e is ReadFailure) e.reason else if(e is java.io.IOException) "network" else "format"
                Log.i("AttendanceRecords","source=background success=false reason=$reason")
                if (!cancelled() && generation==revision.get()) prefs(c).edit().putLong("next",System.currentTimeMillis()+5*60_000).apply()
            } finally { main.post { complete() } }
        }
    }
    private fun notify(c: Context,key: String,name: String) {
        val allowed=c.getSharedPreferences("canvas_announcement_sync",Context.MODE_PRIVATE).getBoolean("notificationsEnabled",false)
        if (!allowed) { Log.i("AttendanceRecords","notification=false reason=app_setting");return }
        if (Build.VERSION.SDK_INT>=33 && c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED) {
            Log.i("AttendanceRecords","notification=false reason=permission");return }
        val nm=c.getSystemService(NotificationManager::class.java)
        if (!nm.areNotificationsEnabled()) { Log.i("AttendanceRecords","notification=false reason=system_setting");return }
        if (Build.VERSION.SDK_INT>=26) nm.createNotificationChannel(NotificationChannel("attendance_tasks","签到提示",NotificationManager.IMPORTANCE_DEFAULT))
        val intent=Intent(c,MainActivity::class.java).putExtra(EXTRA_PENDING,key)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pending=PendingIntent.getActivity(c,key.hashCode(),intent,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder=if(Build.VERSION.SDK_INT>=26) Notification.Builder(c,"attendance_tasks") else Notification.Builder(c)
        nm.notify("attendance",key.hashCode(),builder.setSmallIcon(R.drawable.ic_notification).setContentTitle("发现课程签到")
            .setContentText("$name：尚未签到，开放状态待核实，点击查看").setContentIntent(pending).setAutoCancel(true).build())
        val p=prefs(c);val ids=(p.getStringSet("notifications",emptySet()) ?: emptySet()).toMutableSet()
        ids.add(key.hashCode().toString());p.edit().putStringSet("notifications",ids).apply()
        Log.i("AttendanceRecords","notification=true source=student_records")
    }
    private fun cancelNotifications(c: Context) {
        val p=prefs(c);val manager=c.getSystemService(NotificationManager::class.java)
        p.getStringSet("notifications",emptySet())?.forEach { it.toIntOrNull()?.let { id -> manager.cancel("attendance",id) } }
        p.edit().remove("notifications").apply()
    }
}
class AttendanceJobService : JobService() {
    private var cancelled=java.util.concurrent.atomic.AtomicBoolean(false)
    override fun onStartJob(params: JobParameters): Boolean {
        val flag=java.util.concurrent.atomic.AtomicBoolean(false);cancelled=flag
        AttendanceSync.background(this,{flag.get()}) { if(!flag.get()) jobFinished(params,false) };return true
    }
    override fun onStopJob(params: JobParameters): Boolean {cancelled.set(true);return true}
}
