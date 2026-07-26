package com.example.accurate_step_counter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Reacts to user-initiated changes to wall-clock time, time zone or date so the
 * step counter realises the calendar day shifted without waiting for the next
 * sensor event or the midnight alarm to fire.
 *
 * Without this, a flight from GMT+5:30 to GMT+9 would leave the service
 * convinced it is still "yesterday" and never rotate, causing today's count to
 * accumulate against the previous day's bucket (Apr 17 QA observation 3).
 */
class TimeChangeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        context ?: return
        val action = intent?.action ?: return
        Log.d("TimeChangeReceiver", "Received $action — re-evaluating day boundary")

        // Defer to the service which already knows how to reject backward jumps
        // and rotate forward. Reschedule the midnight alarm too because the
        // previous one was set against the old time zone.
        StepCounterService.handleTimeOrZoneChange(context)
    }
}
