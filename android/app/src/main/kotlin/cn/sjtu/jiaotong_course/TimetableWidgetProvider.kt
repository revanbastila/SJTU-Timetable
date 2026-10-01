package cn.sjtu.jiaotong_course

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.GregorianCalendar
import java.util.Locale
import java.util.TimeZone

/** A self-contained, data-safe home-screen timetable widget. */
class TimetableWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        appWidgetIds.forEach { id -> safelyUpdate(context, manager, id) }
        scheduleMidnightRefresh(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        safelyUpdate(context, manager, appWidgetId)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_REFRESH,
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> updateAll(context)
        }
        if (intent.action?.let { it in REFRESH_ACTIONS } == true) {
            scheduleMidnightRefresh(context)
        }
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        updateAll(context)
        scheduleMidnightRefresh(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        if (AppWidgetManager.getInstance(context)
                .getAppWidgetIds(ComponentName(context, TimetableWidgetProvider::class.java))
                .isEmpty()
        ) cancelMidnightRefresh(context)
    }

    private fun safelyUpdate(context: Context, manager: AppWidgetManager, id: Int) {
        try {
            val options = manager.getAppWidgetOptions(id)
            val height = options.getInt(
                AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT,
                options.getInt(
                    AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT,
                    DEFAULT_MIN_HEIGHT_DP
                )
            )
            val requested = ((height - HEADER_AND_PADDING_DP) / CARD_SLOT_DP)
                .coerceIn(1, COURSE_SLOTS)
            val views = buildViews(context, id, requested)
            manager.updateAppWidget(id, views)
        } catch (_: Throwable) {
            // A malformed/stale snapshot must never prevent widget creation.
            try {
            manager.updateAppWidget(id, placeholderViews(context))
            } catch (_: Throwable) {
                // Launcher owns the host surface; keep receiver failures isolated.
            }
        }
    }

    private fun buildViews(context: Context, widgetId: Int, visibleSlots: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_timetable)
        val today = Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai"))
        val snapshotText = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(SNAPSHOT, null)
        val snapshot = try {
            snapshotText?.let { JSONObject(it) }
        } catch (_: Throwable) {
            null
        }
        val termStart = snapshot?.optString("termStart", "")?.let(::parseDate)
        val savedCourses = snapshot?.optJSONArray("courses")
        // Accept the previous snapshot shape during app upgrades.
        val imported = savedCourses != null &&
            (snapshot?.optBoolean("hasTimetable", savedCourses.length() > 0) ?: false)

        views.setTextViewText(R.id.widget_date, today.get(Calendar.DAY_OF_MONTH).toString())
        val termLabel = snapshot?.optString("termLabel", "").orEmpty()
        val week = termStart?.let { academicWeek(today, it, snapshot?.optInt("totalWeeks", 18) ?: 18) }
        val weekday = weekdayLabel(today.get(Calendar.DAY_OF_WEEK))
        val metadata = when {
            termLabel.isNotBlank() && week != null -> "$termLabel\n第${week}周 · $weekday"
            termLabel.isNotBlank() -> "$termLabel\n$weekday"
            else -> "交大课表\n$weekday"
        }
        views.setTextViewText(R.id.widget_meta, metadata)

        if (!imported) {
            showPlaceholder(views, "打开应用导入课表")
            bindScheduleClick(context, views)
            return views
        }

        // These dated courses were calculated by the shared Dart policy.
        // The old weekday path exists only for snapshots from older APKs.
        val dateKey = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).apply { timeZone = TimeZone.getTimeZone("Asia/Shanghai") }.format(today.time)
        val effectiveDay = snapshot?.optJSONObject("effectiveDays")?.optJSONObject(dateKey)
        val courses = coursesForToday(
            effectiveDay?.optJSONArray("courses") ?: savedCourses ?: JSONArray(),
            today,
            week,
            effectiveDay != null
        )
        Log.i("TeachingCalendar", "widget today=$dateKey effective courses=${courses.size} version=${snapshot?.optString("calendarVersion")} precomputed=${effectiveDay != null}")
        if (courses.isEmpty()) {
            val message = effectiveDay?.optString("emptyMessage", "").orEmpty()
            showPlaceholder(views, message.takeIf { it.isNotBlank() && it != "null" } ?: "今天没有课程")
            bindScheduleClick(context, views)
            return views
        }

        views.setViewVisibility(R.id.widget_empty, View.GONE)
        val prioritized = prioritizeCurrentAndUpcoming(courses, today)
        val chosen = prioritized.take(visibleSlots)
        val allRowIds = listOf(R.id.widget_course_1, R.id.widget_course_2, R.id.widget_course_3)
        allRowIds.forEachIndexed { index, rowId ->
            if (index < chosen.size) {
                val course = chosen[index]
                views.setViewVisibility(rowId, View.VISIBLE)
                populateCourse(views, index, course)
                bindCourseClick(context, views, rowId, course.id)
            } else {
                views.setViewVisibility(rowId, View.GONE)
            }
        }
        val remaining = (prioritized.size - chosen.size).coerceAtLeast(0)
        if (remaining > 0) {
            views.setViewVisibility(R.id.widget_more, View.VISIBLE)
            views.setTextViewText(R.id.widget_more, "还有 $remaining 门")
        } else {
            views.setViewVisibility(R.id.widget_more, View.GONE)
        }
        bindScheduleClick(context, views)
        return views
    }

    private fun populateCourse(views: RemoteViews, index: Int, course: WidgetCourse) {
        val suffix = index + 1
        views.setTextViewText(
            courseTimeId(suffix),
            "${formatTime(course.startHour, course.startMinute)} - " +
                formatTime(course.endHour, course.endMinute)
        )
        views.setTextViewText(courseLocationId(suffix), course.location.ifBlank { "地点未记录" })
        views.setTextViewText(courseTeacherId(suffix), course.teacher)
        views.setTextViewText(courseNameId(suffix), course.name.ifBlank { "课程" })
        views.setImageViewBitmap(courseColorId(suffix), colorDot(course.color))
    }

    private fun coursesForToday(
        source: JSONArray,
        today: Calendar,
        week: Int?,
        precomputed: Boolean = false
    ): List<WidgetCourse> {
        if (!precomputed && week == null) return emptyList()
        val targetWeekday = when (today.get(Calendar.DAY_OF_WEEK)) {
            Calendar.SUNDAY -> 7
            else -> today.get(Calendar.DAY_OF_WEEK) - 1
        }
        val result = mutableListOf<WidgetCourse>()
        for (index in 0 until source.length()) {
            val item = source.optJSONObject(index) ?: continue
            val day = item.optInt("weekday", -1)
            if (!precomputed && day != targetWeekday) continue
            if (!precomputed && !item.optJSONArray("activeWeeks").includes(week ?: 0)) continue
            val startHour = item.optInt("startHour", -1)
            val startMinute = item.optInt("startMinute", 0)
            val endHour = item.optInt("endHour", -1)
            val endMinute = item.optInt("endMinute", 0)
            if (startHour !in 0..23 || endHour !in 0..23 ||
                startMinute !in 0..59 || endMinute !in 0..59
            ) continue
            val id = item.optString("id", item.optString("courseIdentity", ""))
            result.add(
                WidgetCourse(
                    id = id,
                    name = item.optString("name", ""),
                    location = item.optString("location", ""),
                    teacher = item.optString("teacher", ""),
                    startHour = startHour,
                    startMinute = startMinute,
                    endHour = endHour,
                    endMinute = endMinute,
                    startMinutes = startHour * 60 + startMinute,
                    color = item.optInt("widgetColor", DEFAULT_COURSE_COLOR)
                )
            )
        }
        return result.sortedBy { it.startMinutes }
    }

    private fun prioritizeCurrentAndUpcoming(
        courses: List<WidgetCourse>,
        now: Calendar
    ): List<WidgetCourse> {
        val currentMinute = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        val currentIndex = courses.indexOfFirst {
            currentMinute >= it.startMinutes &&
                currentMinute < it.endHour * 60 + it.endMinute
        }
        if (currentIndex >= 0) return courses.drop(currentIndex)
        val nextIndex = courses.indexOfFirst { it.startMinutes >= currentMinute }
        if (nextIndex >= 0) return courses.drop(nextIndex)
        return courses.takeLast(1)
    }

    private fun showPlaceholder(views: RemoteViews, text: String) {
        views.setTextViewText(R.id.widget_empty, text)
        views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
        listOf(R.id.widget_course_1, R.id.widget_course_2, R.id.widget_course_3)
            .forEach { views.setViewVisibility(it, View.GONE) }
        views.setViewVisibility(R.id.widget_more, View.GONE)
    }

    private fun placeholderViews(context: Context): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_timetable)
        val now = Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai"))
        views.setTextViewText(R.id.widget_date, now.get(Calendar.DAY_OF_MONTH).toString())
        views.setTextViewText(R.id.widget_meta, "交大课表\n${weekdayLabel(now.get(Calendar.DAY_OF_WEEK))}")
        showPlaceholder(views, "打开应用导入课表")
        bindScheduleClick(context, views)
        return views
    }

    private fun bindScheduleClick(context: Context, views: RemoteViews) {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            data = android.net.Uri.parse("jiaotong-course://widget/schedule")
        }
        val pending = PendingIntent.getActivity(
            context,
            SCHEDULE_REQUEST,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
        )
        views.setOnClickPendingIntent(R.id.widget_root, pending)
        views.setOnClickPendingIntent(R.id.widget_header, pending)
        views.setOnClickPendingIntent(R.id.widget_empty, pending)
        views.setOnClickPendingIntent(R.id.widget_more, pending)
    }

    private fun bindCourseClick(
        context: Context,
        views: RemoteViews,
        rowId: Int,
        courseId: String
    ) {
        if (courseId.isBlank()) return
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_COURSE_ID, courseId)
            data = android.net.Uri.parse("jiaotong-course://widget/course/${android.net.Uri.encode(courseId)}")
        }
        val pending = PendingIntent.getActivity(
            context,
            courseId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
        )
        views.setOnClickPendingIntent(rowId, pending)
    }

    private fun scheduleMidnightRefresh(context: Context) {
        try {
            val next = Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai")).apply {
                add(Calendar.DAY_OF_YEAR, 1)
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 2)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            val intent = Intent(context, TimetableWidgetProvider::class.java).setAction(ACTION_REFRESH)
            val pending = PendingIntent.getBroadcast(
                context,
                REFRESH_REQUEST,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
            )
            val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarm.setAndAllowWhileIdle(AlarmManager.RTC, next.timeInMillis, pending)
            } else {
                alarm.set(AlarmManager.RTC, next.timeInMillis, pending)
            }
        } catch (_: Throwable) {
            // Broadcasts for date/time/timezone changes remain as refresh fallbacks.
        }
    }

    private fun cancelMidnightRefresh(context: Context) {
        val intent = Intent(context, TimetableWidgetProvider::class.java).setAction(ACTION_REFRESH)
        val pending = PendingIntent.getBroadcast(
            context,
            REFRESH_REQUEST,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
        )
        (context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager)?.cancel(pending)
    }

    private fun colorDot(color: Int): Bitmap {
        val size = 24
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
        canvas.drawRoundRect(RectF(2f, 2f, 22f, 22f), 5f, 5f, paint)
        return bitmap
    }

    private fun parseDate(value: String): Calendar? = try {
        val date = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).apply { isLenient = false; timeZone = TimeZone.getTimeZone("Asia/Shanghai") }.parse(value)
            ?: return null
        Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai")).apply { time = date }
    } catch (_: Throwable) {
        null
    }

    private fun academicWeek(today: Calendar, start: Calendar, totalWeeks: Int): Int? {
        val day = dayNumber(today)
        val first = dayNumber(start)
        if (day < first || day >= first + totalWeeks.coerceAtLeast(1) * 7L) return null
        return ((day - first) / 7L).toInt() + 1
    }

    private fun dayNumber(calendar: Calendar): Long {
        return GregorianCalendar(TimeZone.getTimeZone("UTC")).apply {
            clear()
            set(
                calendar.get(Calendar.YEAR),
                calendar.get(Calendar.MONTH),
                calendar.get(Calendar.DAY_OF_MONTH)
            )
        }.timeInMillis / 86_400_000L
    }

    private fun weekdayLabel(day: Int): String = when (day) {
        Calendar.MONDAY -> "周一"
        Calendar.TUESDAY -> "周二"
        Calendar.WEDNESDAY -> "周三"
        Calendar.THURSDAY -> "周四"
        Calendar.FRIDAY -> "周五"
        Calendar.SATURDAY -> "周六"
        else -> "周日"
    }

    private fun formatTime(hour: Int, minute: Int): String =
        String.format(Locale.ROOT, "%02d:%02d", hour, minute)

    private fun JSONArray?.includes(value: Int): Boolean {
        if (this == null) return true
        if (length() == 0) return true
        for (index in 0 until length()) if (optInt(index, Int.MIN_VALUE) == value) return true
        return false
    }

    private fun immutableFlag(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

    private fun courseTimeId(index: Int) = when (index) {
        1 -> R.id.widget_time_1
        2 -> R.id.widget_time_2
        else -> R.id.widget_time_3
    }
    private fun courseLocationId(index: Int) = when (index) {
        1 -> R.id.widget_location_1
        2 -> R.id.widget_location_2
        else -> R.id.widget_location_3
    }
    private fun courseNameId(index: Int) = when (index) {
        1 -> R.id.widget_name_1
        2 -> R.id.widget_name_2
        else -> R.id.widget_name_3
    }
    private fun courseTeacherId(index: Int) = when (index) {
        1 -> R.id.widget_teacher_1
        2 -> R.id.widget_teacher_2
        else -> R.id.widget_teacher_3
    }
    private fun courseColorId(index: Int) = when (index) {
        1 -> R.id.widget_color_1
        2 -> R.id.widget_color_2
        else -> R.id.widget_color_3
    }

    private data class WidgetCourse(
        val id: String,
        val name: String,
        val location: String,
        val teacher: String,
        val startHour: Int,
        val startMinute: Int,
        val endHour: Int,
        val endMinute: Int,
        val startMinutes: Int,
        val color: Int
    )

    companion object {
        const val PREFS = "timetable_widget"
        const val SNAPSHOT = "snapshot"
        const val PENDING_COURSE_ID = "pending_course_id"
        const val EXTRA_COURSE_ID = "widget_course_id"
        const val ACTION_REFRESH = "cn.sjtu.jiaotong_course.WIDGET_REFRESH"
        private const val SCHEDULE_REQUEST = 52000
        private const val REFRESH_REQUEST = 52001
        private const val DEFAULT_MIN_HEIGHT_DP = 110
        private const val HEADER_AND_PADDING_DP = 61
        private const val CARD_SLOT_DP = 49
        private const val COURSE_SLOTS = 3
        private const val DEFAULT_COURSE_COLOR = 0xFF557A95.toInt()
        private val REFRESH_ACTIONS = setOf(
            ACTION_REFRESH,
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED
        )

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, TimetableWidgetProvider::class.java))
            if (ids.isEmpty()) return
            ids.forEach { id ->
                try {
                    TimetableWidgetProvider().safelyUpdate(context, manager, id)
                } catch (_: Throwable) {
                    // Do not let one stale widget ID break updates for the rest.
                }
            }
        }
    }
}
