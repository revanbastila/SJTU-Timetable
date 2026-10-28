package cn.sjtu.jiaotong_course

fun main() {
    val minute = 60_000L
    val lesson = 10 * 60 * minute
    val end = (11 * 60 + 45) * minute
    val start = lesson - 5 * minute
    val until = end + 5 * minute
    val lookback = lesson - 30 * minute
    val created = (9 * 60 + 41) * minute
    check(!AttendanceWindow.contains(start - 1, created, start, until, lookback))
    check(AttendanceWindow.contains(start, created, start, until, lookback))
    check(AttendanceWindow.contains(until - 1, created, start, until, lookback))
    check(!AttendanceWindow.contains(until, created, start, until, lookback))
    check(AttendanceWindow.contains(start, lookback, start, until, lookback))
    check(!AttendanceWindow.contains(start, lookback - 1, start, until, lookback))
    check(!AttendanceWindow.contains(start, start + 1, start, until, lookback))
    check(!AttendanceWindow.contains(start, created, start, until)) // old config fallback
    check(AttendanceWindow.contains(start, start, start, until))
    println("PASS native reminder/submit window, early record boundaries, future record and old config fallback")
}
