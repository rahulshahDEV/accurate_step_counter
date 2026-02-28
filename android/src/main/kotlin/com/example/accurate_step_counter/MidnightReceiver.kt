package com.example.accurate_step_counter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class MidnightReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        Log.d("MidnightReceiver", "Midnight reset triggered")
        // Reset is applied by StepCounterService when the next sensor event arrives.
    }
}
