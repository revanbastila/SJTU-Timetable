package cn.sjtu.jiaotong_course

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.content.ComponentName
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.webkit.CookieManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Announcement-only polling. Uses WebView's existing session; never logs in. */
object CanvasAnnouncementSync {
    private const val PREFS = "canvas_announcement_sync"
    private const val JOB_ID = 4119
    private const val MIN_INTERVAL = 120_000L
    private const val HOST = "oc.sjtu.edu.cn"
    private val executor = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private val stateLock = Any()

    fun bind(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        channel = MethodChannel(messenger, "cn.sjtu.jiaotong_course/announcements")
        channel!!.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "configure" -> {
                            configure(app, call.argument<String>("account") ?: "",
                                call.argument<String>("catalog") ?: "[]",
                                call.argument<Boolean>("notificationsEnabled") == true,
                                call.argument<List<String>>("known") ?: emptyList())
                            result.success(null)
                        }
                        "cached" -> result.success(cached(app))
                        "refresh" -> {
                            val cookie = CookieManager.getInstance().getCookie("https://$HOST") ?: ""
                            poll(app, cookie) { value -> main.post { result.success(value) } }
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    result.error("announcement_unavailable", "公告后台同步暂不可用", null)
                }
            }
    }

    private fun configure(context: Context, account: String, raw: String,
                          notificationsEnabled: Boolean, known: List<String>) = synchronized(stateLock) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val scheduler = context.getSystemService(JobScheduler::class.java)
        val parsed = JSONArray(raw)
        val catalog = JSONArray()
        val ids = mutableSetOf<String>()
        for (index in 0 until parsed.length()) {
            val item = parsed.optJSONObject(index) ?: continue
            val id = item.optString("id")
            if (id.matches(Regex("[0-9]+")) && ids.add(id)) catalog.put(item)
        }
        if (account.isBlank() || catalog.length() == 0) {
            scheduler.cancel(JOB_ID)
            prefs.edit().clear().putString("revision", UUID.randomUUID().toString()).apply()
            return@synchronized
        }
        val changedAccount = prefs.getString("account", "") != account
        val changedCatalog = prefs.getString("catalog", "") != catalog.toString()
        if (changedAccount || changedCatalog) {
            val edit = prefs.edit()
            if (changedAccount) edit.clear()
            edit.putString("account", account).putString("catalog", catalog.toString())
                .putLong("lastSuccess", 0).putLong("nextAttempt", 0)
                .putString("revision", UUID.randomUUID().toString()).apply()
        }
        val seen = (prefs.getStringSet("seen", emptySet()) ?: emptySet()).toMutableSet()
        seen.addAll(known)
        prefs.edit().putStringSet("seen", seen)
            .putBoolean("notificationsEnabled", notificationsEnabled).apply()
        if (scheduler.getPendingJob(JOB_ID) == null) {
            scheduler.schedule(JobInfo.Builder(JOB_ID,
                ComponentName(context, CanvasAnnouncementJobService::class.java))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                // A silent periodic job cannot run reliably every two minutes.
                // Android may delay this further in Doze or battery saver.
                .setPeriodic(maxOf(15 * 60_000L, JobInfo.getMinPeriodMillis()),
                    maxOf(5 * 60_000L, JobInfo.getMinFlexMillis()))
                .setPersisted(true).build())
        }
    }

    fun cached(context: Context): String = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        .getString("result", "{\"courses\":[]}") ?: "{\"courses\":[]}"

    fun poll(context: Context, cookie: String, cancelled: () -> Boolean = { false },
             completion: (String) -> Unit) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val revision = prefs.getString("revision", "")
        val catalog = prefs.getString("catalog", "[]") ?: "[]"
        val now = System.currentTimeMillis()
        if (cookie.isBlank() || now < prefs.getLong("nextAttempt", 0) ||
            catalog == "[]" || !busy.compareAndSet(false, true)) {
            completion(cached(context))
            return
        }
        prefs.edit().putLong("nextAttempt", now + MIN_INTERVAL).apply()
        executor.execute {
            try {
                val courses = JSONArray(catalog)
                val updates = mutableMapOf<String, JSONObject>()
                val last = prefs.getLong("lastSuccess", 0)
                // Small overlap handles delayed publication/clock skew; ID dedup
                // avoids re-adding messages. Never drop the offline interval.
                val start = if (last > 0 && last <= now) maxOf(0L, last - 120_000L) else 0L
                val format = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", java.util.Locale.ROOT)
                    .apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }
                // Canvas' global endpoint is course-scoped and defaults to a short
                // date window. Explicit bounds also recover announcements after
                // a long offline period. Batch ten courses per request.
                for (offset in 0 until courses.length() step 10) {
                    if (cancelled()) return@execute
                    val batch = (offset until minOf(offset + 10, courses.length()))
                        .map { courses.getJSONObject(it) }
                    val contexts = batch.joinToString("&") {
                        "context_codes%5B%5D=course_${it.getString("id")}"
                    }
                    val path = "/api/v1/announcements?$contexts&per_page=100&latest_only=false" +
                        "&start_date=${URLEncoder.encode(format.format(java.util.Date(start)), "UTF-8")}" +
                        "&end_date=${URLEncoder.encode(format.format(java.util.Date(now + 86_400_000L)), "UTF-8") }"
                    val rows = try { readPages(path, cookie, cancelled) } catch (error: HttpFailure) {
                        // Only use the compatibility endpoint when unavailable;
                        // server/auth/rate-limit failures must retain the cursor.
                        if (error.code !in listOf(400, 403, 404, 405)) throw error
                        null
                    }
                    for (course in batch) {
                        val id = course.getString("id")
                        val scoped = if (rows != null) rows.filter {
                            it.optString("context_code") == "course_$id" || it.optString("course_id") == id
                        } else {
                            readPages("/api/v1/courses/$id/discussion_topics?only_announcements=true&per_page=100",
                                cookie, cancelled)
                        }
                        val items = JSONArray()
                        for (row in scoped) {
                            if (row.optString("id").isBlank()) continue
                            row.put("courseId", id).put("courseName", course.optString("name"))
                                .put("assetId", row.optString("id")).put("type", "公告")
                                .put("createdAt", row.optString("posted_at").ifBlank { row.optString("created_at") })
                            items.put(row)
                        }
                        updates[id] = JSONObject().put("id", id).put("announcements", items)
                    }
                }
                if (cancelled() || prefs.getString("revision", "") != revision) return@execute
                // Accumulate while Flutter is stopped, so a notice doesn't disappear
                // from the native cache before the next app launch.
                val old = JSONObject(cached(context)).optJSONArray("courses") ?: JSONArray()
                for (index in 0 until old.length()) {
                    val previous = old.getJSONObject(index)
                    val current = updates[previous.optString("id")] ?: continue
                    val unique = linkedMapOf<String, JSONObject>()
                    for (array in listOf(previous.getJSONArray("announcements"), current.getJSONArray("announcements"))) {
                        for (i in 0 until array.length()) {
                            val row = array.getJSONObject(i)
                            unique[row.optString("id")] = row
                        }
                    }
                    current.put("announcements", JSONArray(unique.values.toList()))
                }
                val result = JSONObject().put("courses", JSONArray(updates.values.toList())).toString()
                val seen = (prefs.getStringSet("seen", emptySet()) ?: emptySet()).toMutableSet()
                val newItems = mutableListOf<JSONObject>()
                for (course in updates.values) {
                    val rows = course.getJSONArray("announcements")
                    for (i in 0 until rows.length()) {
                        val row = rows.getJSONObject(i)
                        if (seen.add("${course.getString("id")}:${row.optString("id")}")) {
                            // First sync is a baseline, not a historical alert flood.
                            if (last > 0) newItems.add(row)
                        }
                    }
                }
                // Commit cache, cursor and dedup together before notifying.
                synchronized(stateLock) {
                    if (cancelled() || prefs.getString("revision", "") != revision) return@execute
                    check(prefs.edit().putString("result", result).putLong("lastSuccess", now)
                        .putStringSet("seen", seen).commit())
                    if (prefs.getBoolean("notificationsEnabled", false)) {
                        try { notifyNew(context, newItems) } catch (_: Exception) {
                            Log.i("CanvasAnnouncements", "notification unavailable; cache retained")
                        }
                    }
                }
                main.post { channel?.invokeMethod("updated", null) }
                Log.i("CanvasAnnouncements", "synced courses=${updates.size}")
            } catch (_: Exception) {
                // Failed requests never overwrite the last good snapshot or invoke SSO.
                if (prefs.getString("revision", "") == revision) {
                    prefs.edit().putLong("nextAttempt", now + 5 * 60_000L).apply()
                }
                Log.i("CanvasAnnouncements", "sync deferred; cache retained")
            } finally {
                busy.set(false)
                completion(cached(context))
            }
        }
    }

    private class HttpFailure(val code: Int) : Exception()

    private fun notifyNew(context: Context, items: List<JSONObject>) {
        if (items.isEmpty()) return
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(
                Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (!manager.areNotificationsEnabled()) return
        val channelId = "canvas_announcements"
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(channelId, "Canvas 课程公告",
                NotificationManager.IMPORTANCE_DEFAULT))
        }
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return
        val pending = PendingIntent.getActivity(context, 4119, launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        for (item in items) {
            val key = "${item.optString("courseId")}:${item.optString("id")}"
            val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channelId)
                else Notification.Builder(context)
            val notice = builder
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(item.optString("title").ifBlank { "新课程公告" })
                .setContentText("Canvas · ${item.optString("courseName")}")
                .setContentIntent(pending).setAutoCancel(true).setOnlyAlertOnce(true)
                .setCategory(Notification.CATEGORY_MESSAGE).build()
            manager.notify("canvas-announcement", key.hashCode(), notice)
        }
    }

    private fun readPages(path: String, cookie: String, cancelled: () -> Boolean): List<JSONObject> {
        val rows = mutableListOf<JSONObject>()
        var next: String? = "https://$HOST$path"
        var pages = 0
        while (next != null) {
            if (cancelled() || ++pages > 30) throw HttpFailure(0)
            val url = URL(next)
            require(url.protocol == "https" && url.host == HOST && url.path.startsWith("/api/v1/"))
            val connection = url.openConnection() as HttpURLConnection
            try {
                connection.connectTimeout = 10_000
                connection.readTimeout = 15_000
                connection.instanceFollowRedirects = false
                connection.setRequestProperty("Cookie", cookie)
                connection.setRequestProperty("Accept", "application/json")
                if (connection.responseCode != 200) throw HttpFailure(connection.responseCode)
                val data = connection.inputStream.use { input ->
                    val buffer = java.io.ByteArrayOutputStream()
                    val chunk = ByteArray(8192)
                    while (true) {
                        val count = input.read(chunk)
                        if (count < 0) break
                        buffer.write(chunk, 0, count)
                        require(buffer.size() <= 4 * 1024 * 1024)
                    }
                    buffer.toString("UTF-8")
                }
                val parsed = JSONArray(data.removePrefix("while(1);"))
                for (index in 0 until parsed.length()) parsed.optJSONObject(index)?.let(rows::add)
                next = Regex("<([^>]+)>;\\s*rel=\"next\"")
                    .find(connection.getHeaderField("Link") ?: "")?.groupValues?.get(1)
            } finally { connection.disconnect() }
        }
        return rows
    }
}

class CanvasAnnouncementJobService : JobService() {
    private var cancelled = AtomicBoolean(false)
    override fun onStartJob(params: JobParameters): Boolean {
        cancelled = AtomicBoolean(false)
        val token = cancelled
        val cookie = try { CookieManager.getInstance().getCookie("https://oc.sjtu.edu.cn") ?: "" }
            catch (_: Exception) { "" }
        CanvasAnnouncementSync.poll(applicationContext, cookie, { token.get() }) {
            Handler(Looper.getMainLooper()).post { if (!token.get()) jobFinished(params, false) }
        }
        return true
    }
    override fun onStopJob(params: JobParameters): Boolean {
        cancelled.set(true)
        return true
    }
}
