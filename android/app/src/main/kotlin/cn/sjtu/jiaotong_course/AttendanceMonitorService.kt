package cn.sjtu.jiaotong_course

import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.os.*
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/** A single native owner while the UI is absent. Alarms mark class boundaries,
 * never implement the 30-second network loop. No Flutter engine is needed. */
object AttendanceMonitor {
    private const val ALARM = 4128
    fun prefs(c: Context) = c.getSharedPreferences("attendance_v1", Context.MODE_PRIVATE)
    fun windows(c: Context): List<JSONObject> {
        val p = prefs(c)
        if (!p.getBoolean("enabled", false)) return emptyList()
        val a = try { JSONArray(p.getString("windows", "[]")) } catch (_: Exception) { JSONArray() }
        return (0 until a.length()).mapNotNull { a.optJSONObject(it) }
    }
    fun active(c: Context, now: Long = System.currentTimeMillis()) = windows(c).filter {
        now >= it.optLong("start") && now < it.optLong("end")
    }
    private fun alarm(c: Context) = PendingIntent.getBroadcast(c, ALARM,
        Intent(c, AttendanceMonitorReceiver::class.java).setAction("attendance.window"),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun schedule(c: Context, mayStart: Boolean = false) {
        val manager = c.getSystemService(AlarmManager::class.java)
        manager.cancel(alarm(c))
        val now = System.currentTimeMillis()
        val rows = windows(c)
        val current = rows.any { now >= it.optLong("start") && now < it.optLong("end") }
        if (!current) c.stopService(Intent(c, AttendanceMonitorService::class.java))
        else if (mayStart && !prefs(c).getBoolean("monitor_quota", false)) {
            try {
                val intent = Intent(c, AttendanceMonitorService::class.java)
                if (Build.VERSION.SDK_INT >= 26) c.startForegroundService(intent) else c.startService(intent)
                prefs(c).edit().remove("monitor_error").apply()
            } catch (_: Exception) {
                prefs(c).edit().putString("monitor_error", "系统未允许启动后台检测，请打开应用").apply()
                Log.w("AttendanceMonitor", "start=restricted")
            }
        }
        val next = rows.flatMap { listOf(it.optLong("start"), it.optLong("end")) }.filter { it > now }.minOrNull() ?: return
        try {
            if (Build.VERSION.SDK_INT < 31 || manager.canScheduleExactAlarms())
                manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, alarm(c))
            else manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, alarm(c))
        } catch (_: SecurityException) {
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, alarm(c))
        }
    }
    fun status(c: Context): Map<String, Any> {
        val am = c.getSystemService(AlarmManager::class.java)
        return mapOf("running" to AttendanceMonitorService.running,
            "exact" to (Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()),
            "notifications" to c.getSharedPreferences("canvas_announcement_sync", Context.MODE_PRIVATE).getBoolean("notificationsEnabled",false),
            "quota" to prefs(c).getBoolean("monitor_quota", false),
            "error" to (prefs(c).getString("monitor_error", "") ?: ""))
    }
}

class AttendanceMonitorReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // BOOT_COMPLETED cannot launch a dataSync FGS on Android 15+. Only
        // reschedule; a later user-requested exact class alarm may start it.
        AttendanceMonitor.schedule(context, intent.action == "attendance.window")
        AttendanceSync.timeChanged()
    }
}

class AttendanceMonitorService : Service() {
    companion object {
        @Volatile var running = false
        private const val NOTIFICATION = 4128
        private var instance: AttendanceMonitorService? = null
        fun kick() { instance?.let { service -> service.handler.post {
            if (!service.busy && !service.stopped) {
                service.handler.removeCallbacks(service.tick)
                service.handler.postDelayed(service.tick, AttendanceSync.nextAutomaticDelay(service))
            }
        } } }
    }
    private val handler = Handler(Looper.getMainLooper())
    @Volatile private var stopped = false
    private var busy = false
    private var wake: PowerManager.WakeLock? = null
    private val tick = object : Runnable {
        override fun run() {
            if (stopped || busy) return
            val active = AttendanceMonitor.active(this@AttendanceMonitorService)
            if (active.isEmpty()) { stopSelf(); return }
            val boundary = active.maxOf { it.optLong("end") }
            // Bounded to this actual class window; releasing on timeout/destroy
            // is mandatory. Doze/OEM networking restrictions can still apply.
            if (AttendanceSync.isForeground() && wake?.isHeld == true) wake?.release()
            if (!AttendanceSync.isForeground() && wake?.isHeld != true) wake?.acquire((boundary-System.currentTimeMillis()).coerceIn(1, 6*60*60_000L))
            busy = true
            val started = SystemClock.elapsedRealtime()
            Log.i("AttendanceMonitor", "tick elapsed=$started courses=${active.map { it.optString("courseId") }.distinct().joinToString(",")}")
            AttendanceSync.background(this@AttendanceMonitorService, { stopped }, true) {
                busy = false
                if (!stopped) {
                    val next = if (AttendanceSync.isForeground()) 30_000L else AttendanceSync.nextAutomaticDelay(this@AttendanceMonitorService)
                    handler.postDelayed(this, next.coerceAtLeast(1000))
                }
            }
        }
    }
    override fun onCreate() {
        super.onCreate()
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) nm.createNotificationChannel(NotificationChannel(
            "attendance_monitor", "签到后台检测", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, NOTIFICATION, Intent(this, MainActivity::class.java)
            .putExtra(AttendanceSync.EXTRA_PENDING, "monitor"), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "attendance_monitor") else Notification.Builder(this)
        val notification = builder.setSmallIcon(R.drawable.ic_notification).setContentTitle("签到检测运行中")
            .setContentText("课前后检测窗口内，每 30 秒检查；点击打开应用")
            .setContentIntent(open).setOngoing(true).build()
        try {
            if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            else startForeground(NOTIFICATION, notification)
        } catch (_: Exception) {
            AttendanceMonitor.prefs(this).edit().putString("monitor_error", "系统限制后台服务，请打开应用").apply()
            stopSelf(); return
        }
        running = true; instance = this
        wake = getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:attendance")
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (running && !busy) { handler.removeCallbacks(tick); handler.post(tick) }
        return START_NOT_STICKY // No restart loop after user/system stop.
    }
    override fun onTimeout(startId: Int, fgsType: Int) {
        AttendanceMonitor.prefs(this).edit().putBoolean("monitor_quota", true)
            .putString("monitor_error", "后台检测达到系统时限，请打开应用；当前使用系统周期检查").apply()
        Log.w("AttendanceMonitor", "stopped=system_timeout")
        stopSelf()
    }
    override fun onDestroy() {
        stopped = true; running = false; instance = null; handler.removeCallbacksAndMessages(null)
        if (wake?.isHeld == true) wake?.release()
        stopForeground(STOP_FOREGROUND_REMOVE)
        Log.i("AttendanceMonitor", "stopped resources=released")
        super.onDestroy()
    }
    override fun onBind(intent: Intent?) = null
}
