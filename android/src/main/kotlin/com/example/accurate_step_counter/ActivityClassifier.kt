package com.example.accurate_step_counter

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.ActivityRecognitionClient
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionRequest
import com.google.android.gms.location.DetectedActivity
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.ConnectionResult

/**
 * Wraps Google Play Services [ActivityRecognitionClient] to classify what the
 * user is currently doing (walking, running, in vehicle, on bicycle, still).
 *
 * The step counter consults [isInVehicleWindow] before accepting a sensor
 * increment: while the user is in a car or on a bike, TYPE_STEP_COUNTER
 * still fires from road vibration, tram movement, or pedal motion, and
 * counting those events inflates the daily total. Google Fit does the same
 * filtering — that's how its step count stays sane during a commute while
 * the raw Android sensor count balloons.
 *
 * Failure modes:
 *   - Device has no Google Play Services (Huawei HMS-only, some emulators):
 *     [startTracking] is a no-op, [isInVehicleWindow] always returns false,
 *     and the step counter behaves exactly as before. Soft degrade — we
 *     never block the foreground service on this.
 *   - User denies ACTIVITY_RECOGNITION runtime permission: same as above,
 *     soft no-op.
 *   - Transient transition signal loss: we treat the last known state as
 *     persistent until a contradicting transition arrives. A 60-second
 *     "vehicle window" extends past the EXIT transition so stop-and-go
 *     traffic doesn't flap us in and out.
 *
 * Thread safety: state is held in companion @Volatile fields. The broadcast
 * receiver runs on the main thread; the sensor thread reads via
 * [isInVehicleWindow].
 *
 * Round 4 hardening.
 */
class ActivityClassifier {
    companion object {
        private const val TAG = "ActivityClassifier"

        /** Action used by [ActivityTransitionReceiver] PendingIntent. */
        const val ACTION_TRANSITION =
            "com.example.accurate_step_counter.ACTION_ACTIVITY_TRANSITION"

        /** How long after an EXIT vehicle/bicycle transition we still treat
         * the user as "in vehicle". Bridges stop-and-go traffic where the
         * classifier briefly drops to STILL between blocks. */
        const val VEHICLE_GRACE_MS = 60_000L

        /**
         * If we haven't received any transition update in this long, fall
         * back to "unknown" and let the sensor count freely. Trusting a 6-
         * hour-old IN_VEHICLE transition would be worse than no filtering.
         */
        const val MAX_TRANSITION_STALE_MS = 30 * 60_000L

        @Volatile private var lastVehicleEntryElapsedMs: Long = 0L
        @Volatile private var lastVehicleExitElapsedMs: Long = 0L
        @Volatile private var lastBicycleEntryElapsedMs: Long = 0L
        @Volatile private var lastBicycleExitElapsedMs: Long = 0L
        @Volatile private var lastUpdateElapsedMs: Long = 0L

        /** True iff Play Services is reachable on this device. Cached on
         * first probe to avoid repeated reflection. */
        @Volatile private var playServicesAvailable: Boolean? = null

        /** True iff [startTracking] has successfully registered transitions
         * with the system. Reset on [stopTracking]. */
        @Volatile private var trackingActive: Boolean = false

        /**
         * Returns true if the user is currently in a vehicle or on a bicycle,
         * OR was within the last [VEHICLE_GRACE_MS]. Sensor events received
         * during this window are NOT counted as walking steps.
         *
         * When tracking is inactive (no Play Services, no permission, never
         * started) this always returns false — the engine then counts every
         * raw sensor event exactly like the pre-Round-4 behaviour.
         */
        fun isInVehicleWindow(nowElapsedMs: Long): Boolean {
            if (!trackingActive) return false
            // If our state is stale, don't trust the last known classification.
            // Either the user has had Play Services unreachable for a while or
            // we got a corrupted callback. Better to count than to drop.
            if (lastUpdateElapsedMs > 0 &&
                nowElapsedMs - lastUpdateElapsedMs > MAX_TRANSITION_STALE_MS
            ) {
                return false
            }

            // Currently in vehicle = lastEntry > lastExit OR we're within
            // the grace window after the last exit.
            val inVehicleNow = lastVehicleEntryElapsedMs > lastVehicleExitElapsedMs
            val inGraceAfterVehicle = lastVehicleExitElapsedMs > 0 &&
                nowElapsedMs - lastVehicleExitElapsedMs < VEHICLE_GRACE_MS
            val inBicycleNow = lastBicycleEntryElapsedMs > lastBicycleExitElapsedMs
            val inGraceAfterBicycle = lastBicycleExitElapsedMs > 0 &&
                nowElapsedMs - lastBicycleExitElapsedMs < VEHICLE_GRACE_MS

            return inVehicleNow || inGraceAfterVehicle ||
                inBicycleNow || inGraceAfterBicycle
        }

        /**
         * Handle a single ActivityTransition event delivered by the system.
         * Called from [ActivityTransitionReceiver.onReceive] on the main
         * thread.
         */
        fun onTransition(type: Int, transitionType: Int) {
            val now = SystemClock.elapsedRealtime()
            lastUpdateElapsedMs = now
            val isEnter =
                transitionType == ActivityTransition.ACTIVITY_TRANSITION_ENTER
            val verb = if (isEnter) "ENTER" else "EXIT"

            when (type) {
                DetectedActivity.IN_VEHICLE -> {
                    if (isEnter) lastVehicleEntryElapsedMs = now
                    else lastVehicleExitElapsedMs = now
                    Log.d(TAG, "$verb IN_VEHICLE @ $now")
                }
                DetectedActivity.ON_BICYCLE -> {
                    if (isEnter) lastBicycleEntryElapsedMs = now
                    else lastBicycleExitElapsedMs = now
                    Log.d(TAG, "$verb ON_BICYCLE @ $now")
                }
                DetectedActivity.WALKING,
                DetectedActivity.RUNNING,
                DetectedActivity.STILL,
                DetectedActivity.ON_FOOT -> {
                    // Walking / running / still transitions don't need to
                    // mutate vehicle state but stamping the update keeps
                    // staleness math honest.
                    Log.d(TAG, "$verb activity=$type @ $now")
                }
                else -> {
                    // Unknown / tilting — ignored.
                }
            }
        }

        /** Reset all classifier state. Used on logout / account switch. */
        fun reset() {
            lastVehicleEntryElapsedMs = 0L
            lastVehicleExitElapsedMs = 0L
            lastBicycleEntryElapsedMs = 0L
            lastBicycleExitElapsedMs = 0L
            lastUpdateElapsedMs = 0L
        }

        /**
         * Register the transition request with Play Services. Idempotent
         * across repeat calls (returns the cached registration future).
         *
         * Caller MUST hold ACTIVITY_RECOGNITION at runtime. We accept that as
         * a precondition and suppress the lint check because the caller
         * (StepCounterService.startService) only invokes this after the
         * permission gate clears.
         */
        @SuppressLint("MissingPermission")
        fun startTracking(context: Context) {
            if (trackingActive) return
            if (!isPlayServicesAvailable(context)) {
                Log.i(TAG, "Play Services unavailable — activity classifier disabled")
                return
            }
            try {
                val client: ActivityRecognitionClient =
                    ActivityRecognition.getClient(context.applicationContext)

                val transitions = listOf(
                    transition(DetectedActivity.IN_VEHICLE, ActivityTransition.ACTIVITY_TRANSITION_ENTER),
                    transition(DetectedActivity.IN_VEHICLE, ActivityTransition.ACTIVITY_TRANSITION_EXIT),
                    transition(DetectedActivity.ON_BICYCLE, ActivityTransition.ACTIVITY_TRANSITION_ENTER),
                    transition(DetectedActivity.ON_BICYCLE, ActivityTransition.ACTIVITY_TRANSITION_EXIT),
                    transition(DetectedActivity.WALKING, ActivityTransition.ACTIVITY_TRANSITION_ENTER),
                    transition(DetectedActivity.WALKING, ActivityTransition.ACTIVITY_TRANSITION_EXIT),
                    transition(DetectedActivity.RUNNING, ActivityTransition.ACTIVITY_TRANSITION_ENTER),
                    transition(DetectedActivity.RUNNING, ActivityTransition.ACTIVITY_TRANSITION_EXIT),
                    transition(DetectedActivity.STILL, ActivityTransition.ACTIVITY_TRANSITION_ENTER),
                    transition(DetectedActivity.STILL, ActivityTransition.ACTIVITY_TRANSITION_EXIT),
                )
                val request = ActivityTransitionRequest(transitions)

                client.requestActivityTransitionUpdates(request, transitionPendingIntent(context))
                    .addOnSuccessListener {
                        trackingActive = true
                        Log.d(TAG, "Activity transitions registered")
                    }
                    .addOnFailureListener { e ->
                        Log.w(TAG, "Activity transitions registration failed: ${e.message}")
                    }
            } catch (e: SecurityException) {
                Log.w(TAG, "ACTIVITY_RECOGNITION not granted — classifier disabled")
            } catch (e: Exception) {
                Log.w(TAG, "Activity classifier start failed: ${e.message}")
            }
        }

        /** Unregister transition updates. Safe to call when never started. */
        fun stopTracking(context: Context) {
            if (!trackingActive) return
            try {
                val client = ActivityRecognition.getClient(context.applicationContext)
                client.removeActivityTransitionUpdates(transitionPendingIntent(context))
                    .addOnCompleteListener {
                        trackingActive = false
                        Log.d(TAG, "Activity transitions unregistered")
                    }
            } catch (e: Exception) {
                Log.w(TAG, "Activity classifier stop failed: ${e.message}")
                trackingActive = false
            }
        }

        private fun transition(type: Int, transitionType: Int): ActivityTransition =
            ActivityTransition.Builder()
                .setActivityType(type)
                .setActivityTransition(transitionType)
                .build()

        // Unique RC so FLAG_UPDATE_CURRENT cannot clobber midnight/notification
        // PendingIntents that also use request-code 0 in host apps / other plugins.
        private const val RC_ACTIVITY_TRANSITION = 0x4154_5258 // "ATRX"

        private fun transitionPendingIntent(context: Context): PendingIntent {
            // Explicit component is required for reliable delivery on Android 8+
            // (implicit package broadcasts are restricted; dynamic receivers alone
            // are not enough once Play Services fires the PendingIntent).
            val intent = Intent(context, ActivityTransitionReceiver::class.java).apply {
                action = ACTION_TRANSITION
            }
            // FLAG_MUTABLE required by ActivityRecognitionClient on API 31+
            // (the receiver mutates the intent extras with the result).
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            return PendingIntent.getBroadcast(context, RC_ACTIVITY_TRANSITION, intent, flags)
        }

        private fun isPlayServicesAvailable(context: Context): Boolean {
            val cached = playServicesAvailable
            if (cached != null) return cached
            val result = try {
                GoogleApiAvailability.getInstance()
                    .isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS
            } catch (e: Throwable) {
                false
            }
            playServicesAvailable = result
            return result
        }
    }
}
