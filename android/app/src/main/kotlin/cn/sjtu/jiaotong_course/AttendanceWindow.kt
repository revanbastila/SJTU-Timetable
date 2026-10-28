package cn.sjtu.jiaotong_course

/** Shared by reminder eligibility and the final native submit guard. */
internal object AttendanceWindow {
    fun contains(now: Long, created: Long, start: Long, end: Long, recordStart: Long = start): Boolean =
        now >= start && now < end && created >= recordStart && created < end && created <= now
}
