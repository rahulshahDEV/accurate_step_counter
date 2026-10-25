package com.example.accurate_step_counter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class MidnightReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        Log.d("MidnightReceiver", "Midnight reset triggered")
        context ?: return
        if (!StepCounterService.isTrackingEnabled(context)) return

        // Force day rotation in the step counter service
        try {
            StepCounterService.performMidnightReset(context)
        } finally {
            // A rejected/already-restored rotation still needs tomorrow's alarm.
            StepCounterService.scheduleMidnightAlarm(context)
        }
    }
}
