package cn.sjtu.jiaotong_course

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
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

    fun bind(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, "cn.sjtu.jiaotong_course/announcements")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "configure" -> {
                            configure(app, call.argument<String>("account") ?: "",
                                call.argument<String>("catalog") ?: "[]")
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

    private fun configure(context: Context, account: String, raw: String) {
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
            return
        }
        val changedAccount = prefs.getString("account", "") != account
        if (changedAccount || prefs.getString("catalog", "") != catalog.toString()) {
            val edit = prefs.edit()
            if (changedAccount) edit.clear()
            edit.putString("account", account).putString("catalog", catalog.toString())
                .putString("revision", UUID.randomUUID().toString()).apply()
        }
        if (scheduler.getPendingJob(JOB_ID) == null) {
            scheduler.schedule(JobInfo.Builder(JOB_ID,
                ComponentName(context, CanvasAnnouncementJobService::class.java))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setPeriodic(15 * 60_000L, 5 * 60_000L)
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
                val start = if (last > 0) minOf(now - 7 * 86_400_000L, last - 86_400_000L) else 0L
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
                        if (error.code == 401 || error.code == 429) throw error
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
                prefs.edit().putString("result", result).putLong("lastSuccess", now).apply()
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
