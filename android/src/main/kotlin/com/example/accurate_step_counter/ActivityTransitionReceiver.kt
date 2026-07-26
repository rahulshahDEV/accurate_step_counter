package com.example.accurate_step_counter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.ActivityTransitionResult

/**
 * Broadcast receiver that the Activity Transitions API hits when the user
 * transitions between activity classes (WALKING / RUNNING / IN_VEHICLE /
 * ON_BICYCLE / STILL). Hands each event to [ActivityClassifier] which
 * maintains the in-memory state the step counter consults.
 *
 * Registered in the plugin manifest and targeted by an explicit PendingIntent
 * from [ActivityClassifier]. Dynamic registration is intentionally avoided
 * so Play Services delivers exactly once to this component.
 *
 * Round 4 hardening.
 */
class ActivityTransitionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent == null) return
        if (intent.action != ActivityClassifier.ACTION_TRANSITION) return
        if (!ActivityTransitionResult.hasResult(intent)) {
            Log.w(TAG, "transition broadcast missing result payload")
            return
        }
        val result = ActivityTransitionResult.extractResult(intent) ?: return
        for (event in result.transitionEvents) {
            ActivityClassifier.onTransition(event.activityType, event.transitionType)
        }
    }

    companion object {
        private const val TAG = "ActivityTransRx"
    }
}
