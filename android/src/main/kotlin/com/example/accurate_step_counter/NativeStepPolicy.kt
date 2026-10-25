package com.example.accurate_step_counter

import java.util.Calendar
import java.util.TimeZone

/** Pure rules shared by service restore and live rotation. */
internal object NativeStepPolicy {
    const val MIN_ROTATION_MS = 16 * 60 * 60 * 1000L

    fun dayDifference(oldYear: Int, oldDay: Int, newYear: Int, newDay: Int): Int {
        fun utcDate(year: Int, day: Int) = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
            clear()
            set(Calendar.YEAR, year)
            set(Calendar.DAY_OF_YEAR, day)
        }.timeInMillis
        return ((utcDate(newYear, newDay) - utcDate(oldYear, oldDay)) / 86400000L).toInt()
    }

    fun startOfDay(nowWall: Long, zone: TimeZone = TimeZone.getDefault()): Long =
        Calendar.getInstance(zone).apply {
            timeInMillis = nowWall
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis

    fun nextMidnight(nowWall: Long, zone: TimeZone = TimeZone.getDefault()): Long =
        Calendar.getInstance(zone).apply {
            timeInMillis = nowWall
            add(Calendar.DAY_OF_MONTH, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 5)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis

    fun canRotate(nowElapsed: Long, nowWall: Long, lastElapsed: Long, lastWall: Long): Boolean {
        if (lastElapsed > 0 && nowElapsed >= lastElapsed &&
            nowElapsed - lastElapsed < MIN_ROTATION_MS) return false
        if (lastWall > 0 && nowWall - lastWall < MIN_ROTATION_MS) return false
        return true
    }

    fun restoredOffset(today: Int, baseline: Int?, lastBootSteps: Int): Int =
        (today - if (baseline != null && lastBootSteps >= baseline) {
            lastBootSteps - baseline
        } else 0).coerceAtLeast(0)

    fun recoveryAllowance(elapsedMs: Long, perHour: Int = 9000, perMinute: Int = 180): Int =
        (elapsedMs.coerceIn(0, 24 * 60 * 60 * 1000L) / 1000 * perHour / 3600 + perMinute)
            .coerceAtMost(80000).toInt()

    fun admitRecovery(requested: Int, elapsedMs: Long, perHour: Int, perMinute: Int): Int =
        requested.coerceAtLeast(0).coerceAtMost(recoveryAllowance(elapsedMs, perHour, perMinute))

    fun detectorMismatch(delta: Int, evidence: Int, now: Long, lastDetector: Long, firstCounter: Boolean): Boolean =
        !firstCounter && lastDetector > 0 && now - lastDetector in 0..30000 &&
            delta >= 4 && evidence * 2 < delta
}
