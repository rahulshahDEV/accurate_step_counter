package com.example.accurate_step_counter

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.hardware.*
import android.os.*
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import java.util.*

class StepCounterService : Service(), SensorEventListener {
    companion object {
        const val TAG = "StepCounter"
        const val CHANNEL_ID = "step_counter_channel"
        const val NOTIFICATION_ID = 1
        const val ACTION_STEPS_UPDATE = "com.example.accurate_step_counter.STEPS_UPDATE"
        const val EXTRA_STEPS = "steps"

        private const val PREFS_NAME = "step_counter_prefs"
        private const val KEY_BOOT_BASELINE = "boot_baseline"
        private const val KEY_TODAY_STEPS = "today_steps"
        private const val KEY_YESTERDAY_STEPS = "yesterday_steps"
        private const val KEY_DAY_BEFORE_STEPS = "day_before_steps"
        private const val KEY_LAST_RESET_DAY = "last_reset_day"
        private const val KEY_LAST_RESET_YEAR = "last_reset_year"
        private const val KEY_LAST_BOOT_COUNT = "last_boot_count"
        // Date stamp written by performMidnightReset / handleTimeOrZoneChange so
        // the Flutter cubit can detect "service rotated the day while we were
        // backgrounded" even if the LocalBroadcast was lost (Apr 27 Bug 2 —
        // Samsung A07 nightly rollover not surfacing in UI when serviceInstance
        // was null because the OS had killed the foreground service).
        const val KEY_LAST_ROTATION_DATE = "last_rotation_date"
        // Snapshot of the day's tally at the moment we rolled over, so the
        // Flutter side can reliably restore yesterday from the same source the
        // native rotation used.
        const val KEY_LAST_ROTATION_PREV_TODAY = "last_rotation_prev_today"

        // Unique PendingIntent request codes so third-party plugin code that
        // also uses rc=0 doesn't accidentally overwrite our intents via
        // FLAG_UPDATE_CURRENT (native audit May 28 HIGH).
        private const val RC_MIDNIGHT_ALARM = 0x4D44_4E54 // "MDNT"
        private const val RC_NOTIFICATION_TAP = 0x4D44_4E54 + 1

        // Minimum step increment to accept (filters micro-vibrations and phantom steps)
        private const val MIN_STEP_INCREMENT = 4
        // Minimum time between accepted step updates (ms)
        private const val MIN_UPDATE_INTERVAL_MS = 1000L
        // Persist state every N accepted updates. Disk writes through apply()
        // are async + batched by the Android framework so persisting on every
        // accepted update is cheap and guarantees minimal data loss when the
        // user force-closes (Apr 17 OPPO A15 observation 4).
        private const val PERSIST_EVERY_N_UPDATES = 1
        // Maximum realistic steps per second (running cadence ~4 steps/sec).
        // Used as a short-window burst guard. The longer per-minute guard
        // below catches sustained overcounting that this short window misses.
        private const val MAX_STEPS_PER_SECOND = 5
        // Sustained ceiling: even an elite runner caps at ~210 steps/min on
        // a track and most casual users sit under 130. Samsung TYPE_STEP_COUNTER
        // is known to drift well above this on some devices (Apr 17 A07 reported
        // 75% over G-Fit; Apr 27 same device hit 122% over G-Fit). Tightened
        // from 240 -> 180 since 240 still left room for ~6.5h of inflated
        // walking before a real user could care, and the actual sustained walk
        // ceiling (~150) gives us safety margin without clipping legitimate
        // running. Anything beyond this rate over a 60s window is dropped.
        private const val MAX_STEPS_PER_MINUTE = 180
        private const val ONE_MINUTE_MS = 60_000L
        // Hourly ceiling: layered on top of the per-minute cap. The minute cap
        // alone allowed 180*60=10 800 steps/h sustained, which a Samsung A07
        // running at 2x ground truth could still hit and bury us under
        // overcount over a long day. A real walker doing ~150 cadence does
        // 9000 in an hour at the very most; runners hit 11k+ but rarely
        // sustained for a full hour. 9000 keeps casual+brisk walking lossless
        // while clipping persistent sensor drift (May 10 QA — sensor
        // 9079 vs G-Fit 4572 = 98% over without HC for cross-validation).
        private const val MAX_STEPS_PER_HOUR = 9000
        private const val ONE_HOUR_MS = 60 * 60_000L
        // Minimum monotonic time (ms) between day resets — protects against
        // time manipulation. Tuned to 16h to match the cubit-side
        // _kMinForwardRolloverMonotonicMs so Dart and Kotlin never disagree
        // on whether a rotation is legit (audit finding May 28). 16h covers
        // even the most extreme TZ jumps (Australia <-> US ~16-19h) while
        // still blocking rapid-fire fake rollovers via clock spin.
        private const val MIN_RESET_INTERVAL_MS = 16 * 3600 * 1000L  // 16 hours

        // All companion state below is mutated from multiple threads — the
        // sensor binder thread (`onSensorChanged`), the main thread
        // (MethodChannel handlers), and various BroadcastReceiver dispatch
        // threads (MidnightReceiver, TimeChangeReceiver, BootReceiver). We
        // funnel every mutation through the `STATE_LOCK` monitor below so
        // ArrayDeque ops can't throw ConcurrentModificationException and
        // the rolling totals can't desync from the deques (native audit
        // finding May 28).
        private val STATE_LOCK = Any()

        @Volatile private var initialOffset = 0
        @Volatile private var sensorFloor = 0
        @Volatile private var bootStepsBaseline: Int? = null
        @Volatile private var todaySteps = 0
        @Volatile private var yesterdaySteps = 0
        @Volatile private var dayBeforeSteps = 0
        @Volatile private var lastResetDay = -1
        @Volatile private var lastResetYear = -1
        @Volatile private var isRunning = false

        // Monotonic clock at last day reset — can't be manipulated by user
        @Volatile private var lastResetElapsedTime = 0L

        // Debounce state
        @Volatile private var lastAcceptedBootSteps = -1
        @Volatile private var lastAcceptedTime = 0L
        @Volatile private var pendingSteps = 0
        @Volatile private var updatesSincePersist = 0

        // Sliding 60s window for sustained-rate enforcement. ArrayDeque is
        // NOT thread-safe — all access goes through `STATE_LOCK`.
        // Each entry is (monotonicMs, stepsAccepted). Pruned to last minute.
        private val recentAcceptedSteps: ArrayDeque<Pair<Long, Int>> = ArrayDeque()
        @Volatile private var recentAcceptedTotal = 0
        // Sliding 60-min window for the hourly sustained-rate enforcement.
        // Same shape as the minute window above, just at coarser granularity.
        private val hourlyAcceptedSteps: ArrayDeque<Pair<Long, Int>> = ArrayDeque()
        @Volatile private var hourlyAcceptedTotal = 0

        // Round 4 step-detector cross-check. TYPE_STEP_DETECTOR fires
        // once per genuinely detected step; we count those between
        // accepted TYPE_STEP_COUNTER batches and reject COUNTER deltas
        // that have no corresponding DETECTOR evidence (pure vibration).
        @Volatile private var lastDetectorEventElapsedMs: Long = 0L
        @Volatile private var detectorEventsSinceLastCounterAccept: Int = 0

        // Service instance reference for notification updates from companion.
        // @Volatile ensures cross-thread visibility — read from receiver
        // threads, written from main thread in onCreate/onDestroy.
        @Volatile private var serviceInstance: StepCounterService? = null

        fun getTodaySteps(): Int = todaySteps
        fun getYesterdaySteps(): Int = yesterdaySteps
        fun getDayBeforeSteps(): Int = dayBeforeSteps

        /** Whether the foreground service is currently running. */
        fun isServiceRunning(): Boolean = isRunning

        /**
         * Returns the most recent rotation stamp the service wrote — date plus
         * the today-tally snapshot at the moment of rotation — and clears it.
         * The Flutter cubit polls this on resume / on the periodic timer to
         * recover from a missed midnight broadcast (Apr 27 Bug 2). The clear-
         * on-read semantics make the call idempotent: a second consumer in the
         * same process gets nulls and won't double-rotate.
         */
        fun consumeLastRotation(context: Context): Map<String, Any>? {
            return try {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val date = prefs.getString(KEY_LAST_ROTATION_DATE, null) ?: return null
                val prev = prefs.getInt(KEY_LAST_ROTATION_PREV_TODAY, 0)
                prefs.edit()
                    .remove(KEY_LAST_ROTATION_DATE)
                    .remove(KEY_LAST_ROTATION_PREV_TODAY)
                    .apply()
                mapOf("date" to date, "previousToday" to prev)
            } catch (e: Exception) {
                Log.w(TAG, "consumeLastRotation failed: ${e.message}")
                null
            }
        }

        fun setInitialOffset(offset: Int) {
            // Lock against onSensorChanged so the recalculation doesn't tear
            // a baseline / lastAcceptedBootSteps read between the two
            // independent fetches and produce a wrong todaySteps. Round 3.
            synchronized(STATE_LOCK) {
                initialOffset = offset
                val baseline = bootStepsBaseline
                todaySteps = if (baseline != null && lastAcceptedBootSteps >= 0) {
                    (lastAcceptedBootSteps - baseline).coerceAtLeast(0) + initialOffset + sensorFloor
                } else {
                    initialOffset + sensorFloor
                }
                serviceInstance?.let {
                    it.broadcastSteps(todaySteps)
                    it.updateNotification(todaySteps)
                }
                Log.d(TAG, "Initial offset set to $offset, todaySteps recalculated to $todaySteps")
            }
        }

        fun setSensorFloor(floor: Int) {
            synchronized(STATE_LOCK) {
                sensorFloor = floor
                val baseline = bootStepsBaseline
                todaySteps = if (baseline != null && lastAcceptedBootSteps >= 0) {
                    (lastAcceptedBootSteps - baseline).coerceAtLeast(0) + initialOffset + sensorFloor
                } else {
                    initialOffset + sensorFloor
                }
                serviceInstance?.let {
                    it.broadcastSteps(todaySteps)
                    it.updateNotification(todaySteps)
                }
                Log.d(TAG, "Sensor floor set to $floor, todaySteps recalculated to $todaySteps")
            }
        }

        fun needsCalibration(): Boolean {
            // Only calibrate if we've never received a sensor event (baseline null).
            // Don't trigger on todaySteps==0 (legitimate after midnight rollover).
            return bootStepsBaseline == null
        }

        /**
         * Force-set the displayed step count. Used by Flutter to sync notification
         * with merged value (HC + sensor + server) so notification matches app UI.
         * Adjusts initialOffset so future sensor increments stack on top of [value].
         */
        fun forceUpdateTodaySteps(value: Int) {
            if (value < 0) return
            synchronized(STATE_LOCK) {
                val baseline = bootStepsBaseline
                if (baseline != null && lastAcceptedBootSteps >= 0) {
                    val rawDelta = (lastAcceptedBootSteps - baseline).coerceAtLeast(0)
                    initialOffset = (value - rawDelta - sensorFloor).coerceAtLeast(0)
                } else {
                    initialOffset = value
                    sensorFloor = 0
                }
                todaySteps = value
                serviceInstance?.let {
                    it.broadcastSteps(todaySteps)
                    it.updateNotification(todaySteps)
                }
                Log.d(TAG, "Force-updated todaySteps to $value (offset=$initialOffset)")
            }
        }

        /**
         * Update ONLY the notification text without touching any sensor state.
         *
         * Used by the cubit to keep the foreground notification in sync with
         * the merged display value (HC + sensor) without poisoning the
         * native bootStepsBaseline / initialOffset / sensorFloor that
         * [forceUpdateTodaySteps] mutates. May 22 QA obs 2: notification
         * showed 780 (raw sensor) while app showed 6284 (HC-merged) —
         * before the May 31 fix we used forceUpdateTodaySteps to fix that
         * lag, but it ended up baking transient HC inflations into the
         * sensor count for the rest of the day. This decoupled call gives
         * us the notification sync without the side effect.
         */
        fun setNotificationDisplay(value: Int) {
            if (value < 0) return
            serviceInstance?.updateNotification(value)
        }

        /** Clear all in-memory step state. Used on logout / account switch. */
        fun resetState(context: Context) {
            synchronized(STATE_LOCK) {
                initialOffset = 0
                sensorFloor = 0
                bootStepsBaseline = null
                todaySteps = 0
                yesterdaySteps = 0
                dayBeforeSteps = 0
                lastResetDay = -1
                lastResetYear = -1
                lastResetElapsedTime = 0L
                lastAcceptedBootSteps = -1
                lastAcceptedTime = 0L
                pendingSteps = 0
                updatesSincePersist = 0
                recentAcceptedSteps.clear()
                recentAcceptedTotal = 0
                hourlyAcceptedSteps.clear()
                hourlyAcceptedTotal = 0
                // Round 4: also wipe step-detector cross-check + vehicle
                // window so a new user doesn't inherit the previous
                // user's transient state.
                lastDetectorEventElapsedMs = 0L
                detectorEventsSinceLastCounterAccept = 0
            }
            ActivityClassifier.reset()

            // Clear persisted state
            try {
                context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    .edit().clear().apply()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to clear prefs: ${e.message}")
            }

            Log.d(TAG, "State fully reset (logout/account switch)")
        }

        /**
         * Force midnight day rotation from MidnightReceiver.
         * Called when alarm fires at midnight — handles the case where no sensor events
         * arrive at midnight so onSensorChanged day-change detection doesn't trigger.
         */
        fun performMidnightReset(context: Context) {
            // The whole reset is now under STATE_LOCK so the AlarmManager
            // thread cannot interleave with a sensor-thread mutation of
            // bootStepsBaseline / todaySteps / pendingSteps mid-rollover
            // and corrupt the rotation (Round 3 hardening — audit F5).
            // Variables that need to survive the lock for use after it
            // (rotationDate, previousToday, currentDay, currentYear) are
            // hoisted into the outer scope.
            val cal = Calendar.getInstance()
            val currentDay = cal.get(Calendar.DAY_OF_YEAR)
            val currentYear = cal.get(Calendar.YEAR)
            var previousToday = 0
            var rotationDate = ""
            var didRotate = false

            synchronized(STATE_LOCK) {
                // Only reset if the day actually changed
                if (currentDay == lastResetDay && currentYear == lastResetYear) {
                    Log.d(TAG, "Midnight reset skipped — day unchanged")
                    return
                }

                // Monotonic guard against time-manipulation: refuse the rotation
                // if less than MIN_RESET_INTERVAL_MS of real elapsedRealtime has
                // passed since the previous reset, regardless of which calendar
                // day the wall clock claims. Same defence the backward branch
                // already uses, extended to forward jumps (May 26 obs 8 + 9 —
                // manually winding the clock to mint a fresh day of rewards).
                val nowMono = SystemClock.elapsedRealtime()
                val elapsedMono = nowMono - lastResetElapsedTime
                if (lastResetElapsedTime > 0 && elapsedMono < MIN_RESET_INTERVAL_MS) {
                    Log.w(
                        TAG,
                        "performMidnightReset rejected on monotonic guard: ${elapsedMono / 1000}s real-time since last reset (need ${MIN_RESET_INTERVAL_MS / 1000}s)"
                    )
                    return
                }

                previousToday = todaySteps
                rotationDate = String.format(
                    Locale.US,
                    "%04d-%02d-%02d",
                    cal.get(Calendar.YEAR),
                    cal.get(Calendar.MONTH) + 1,
                    cal.get(Calendar.DAY_OF_MONTH)
                )

                dayBeforeSteps = yesterdaySteps
                yesterdaySteps = todaySteps
                todaySteps = 0
                initialOffset = 0
                sensorFloor = 0
                lastResetDay = currentDay
                lastResetYear = currentYear
                lastResetElapsedTime = SystemClock.elapsedRealtime()
                pendingSteps = 0
                updatesSincePersist = 0
                recentAcceptedSteps.clear()
                recentAcceptedTotal = 0
                hourlyAcceptedSteps.clear()
                hourlyAcceptedTotal = 0

                // Re-baseline on next sensor event
                bootStepsBaseline = null
                lastAcceptedBootSteps = -1
                didRotate = true
            }

            // If we hit either early-return path inside the lock above,
            // Kotlin's inline `synchronized` already returned from
            // performMidnightReset. didRotate is only true when we made
            // it through the full rollover block.
            if (!didRotate) return

            // Persist rotated state
            try {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                prefs.edit().apply {
                    putInt(KEY_BOOT_BASELINE, -1)
                    putInt(KEY_TODAY_STEPS, 0)
                    putInt(KEY_YESTERDAY_STEPS, yesterdaySteps)
                    putInt(KEY_DAY_BEFORE_STEPS, dayBeforeSteps)
                    putInt(KEY_LAST_RESET_DAY, currentDay)
                    putInt(KEY_LAST_RESET_YEAR, currentYear)
                    putInt(KEY_LAST_BOOT_COUNT, -1)
                    putString(KEY_LAST_ROTATION_DATE, rotationDate)
                    putInt(KEY_LAST_ROTATION_PREV_TODAY, previousToday)
                    apply()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to persist midnight reset: ${e.message}")
            }

            // Update notification and broadcast 0 to Flutter
            serviceInstance?.let {
                it.broadcastSteps(0)
                it.updateNotification(0)
            }

            Log.d(TAG, "Midnight reset: yesterday=$yesterdaySteps, dayBefore=$dayBeforeSteps")

            // Schedule next midnight alarm
            scheduleMidnightAlarm(context)
        }

        /**
         * Handle a system time, date or time-zone change initiated by the user.
         *
         * Walks the same forward/backward decision as a normal sensor-driven
         * day check: if the wall clock is now on a new calendar day relative to
         * the last reset, perform a midnight rotation; if it appears to have
         * gone backward we leave state intact (anti time-manipulation, same
         * 20h guard as onSensorChanged uses).
         *
         * Either way the next midnight alarm is rescheduled against the new
         * time zone so the daily reset still lands at local midnight.
         */
        fun handleTimeOrZoneChange(context: Context) {
            val cal = Calendar.getInstance()
            val currentDay = cal.get(Calendar.DAY_OF_YEAR)
            val currentYear = cal.get(Calendar.YEAR)

            val dayChanged = currentDay != lastResetDay || currentYear != lastResetYear
            if (dayChanged) {
                val isBackward = currentYear < lastResetYear ||
                    (currentYear == lastResetYear && currentDay < lastResetDay)
                val now = SystemClock.elapsedRealtime()
                val elapsedSinceReset = now - lastResetElapsedTime
                // Symmetric monotonic guard for forward and backward TZ shifts
                // (May 26 obs 8 + 9 — manual time change attack mitigation).
                if (lastResetElapsedTime > 0 &&
                    elapsedSinceReset < MIN_RESET_INTERVAL_MS
                ) {
                    Log.w(
                        TAG,
                        "TZ/time change rejected on monotonic guard: ${elapsedSinceReset / 1000}s since last reset (isBackward=$isBackward)"
                    )
                } else {
                    Log.d(TAG, "TZ/time change crossed day boundary — performing rotation")
                    performMidnightReset(context)
                    return // performMidnightReset already reschedules the alarm
                }
            }

            // Same day after the change but the alarm we previously set was
            // pinned to the old time zone — replace it so reset still lands
            // at local midnight in the new zone.
            scheduleMidnightAlarm(context)
        }

        /** Schedule an exact alarm for next midnight. Replaces inexact setRepeating. */
        fun scheduleMidnightAlarm(context: Context) {
            try {
                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val intent = Intent(context, MidnightReceiver::class.java)
                val pendingIntent = PendingIntent.getBroadcast(
                    context, RC_MIDNIGHT_ALARM, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )

                // Use java.time for DST-safe scheduling. The old Calendar
                // approach (set HOUR=0, then add(DAY, 1)) could land on a
                // non-existent local time during spring-forward (00:00 may
                // not exist that day in some zones) or fire twice during
                // fall-back (native audit May 28 HIGH). 00:00:05 keeps the
                // 5s margin so we land just past the boundary.
                val zone = java.time.ZoneId.systemDefault()
                val tomorrowMidnight = java.time.LocalDate.now(zone)
                    .plusDays(1)
                    .atStartOfDay(zone)
                    .plusSeconds(5)
                val triggerAtMillis = tomorrowMidnight.toInstant().toEpochMilli()
                val midnight = Calendar.getInstance().apply {
                    timeInMillis = triggerAtMillis
                }

                // Use exact alarm for reliable midnight reset.
                // On Android 12+ (API 31), setExactAndAllowWhileIdle requires
                // SCHEDULE_EXACT_ALARM permission. Fall back to inexact if denied.
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        alarmManager.setExactAndAllowWhileIdle(
                            AlarmManager.RTC_WAKEUP,
                            triggerAtMillis,
                            pendingIntent
                        )
                    } else {
                        alarmManager.setExact(
                            AlarmManager.RTC_WAKEUP,
                            triggerAtMillis,
                            pendingIntent
                        )
                    }
                } catch (se: SecurityException) {
                // SCHEDULE_EXACT_ALARM not granted on Android 12+ — fall
                // back to inexact while-idle. Midnight may drift by minutes
                // until the next sensor day-check or app resume drain.
                    Log.w(TAG, "Exact alarm denied, using inexact fallback: ${se.message}")
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAtMillis,
                        pendingIntent
                    )
                }

                Log.d(TAG, "Next midnight alarm scheduled at ${midnight.time}")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to schedule midnight alarm: ${e.message}")
            }
        }
    }

    private var sensorManager: SensorManager? = null
    private var stepSensor: Sensor? = null
    private var stepDetectorSensor: Sensor? = null
    private var timeChangeReceiver: TimeChangeReceiver? = null

    override fun onCreate() {
        super.onCreate()
        serviceInstance = this
        createNotificationChannel()
        startForegroundSafely()

        // Restore persisted state before registering sensor
        restoreState()

        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        stepSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)

        stepSensor?.let {
            sensorManager?.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL)
            isRunning = true
            Log.d(TAG, "Step sensor registered (baseline=${bootStepsBaseline}, today=$todaySteps)")
        } ?: Log.e(TAG, "No step counter sensor found")

        // Register TYPE_STEP_DETECTOR alongside TYPE_STEP_COUNTER. Detector
        // fires once per detected step (rather than reporting the cumulative
        // since-boot total like counter does), which lets the engine cross-
        // check that COUNTER increments are backed by genuine detected
        // steps and not phantom vibration / sensor drift (Round 4).
        stepDetectorSensor =
            sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)
        stepDetectorSensor?.let {
            sensorManager?.registerListener(
                this,
                it,
                SensorManager.SENSOR_DELAY_NORMAL,
            )
            Log.d(TAG, "Step detector registered for cross-check")
        }

        // Activity transitions classifier. Manifest-declared
        // ActivityTransitionReceiver is the explicit PendingIntent target;
        // do not also register dynamically (would risk double-handling).
        try {
            ActivityClassifier.startTracking(this)
        } catch (e: Exception) {
            Log.w(TAG, "Activity classifier setup failed (soft-degrade): ${e.message}")
        }

        // Listen for user-driven time / time-zone changes so the day rotates
        // even when the user crosses midnight via flight or manual change.
        // Registering at runtime (vs manifest) keeps the receiver alive only
        // while the foreground service is running, which is the only window
        // where it can usefully drive UI / notification updates.
        try {
            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_TIMEZONE_CHANGED)
                addAction(Intent.ACTION_TIME_CHANGED)
                addAction(Intent.ACTION_DATE_CHANGED)
            }
            timeChangeReceiver = TimeChangeReceiver().also {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    registerReceiver(it, filter, RECEIVER_NOT_EXPORTED)
                } else {
                    @Suppress("UnspecifiedRegisterReceiverFlag")
                    registerReceiver(it, filter)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register TimeChangeReceiver: ${e.message}")
        }

        // Update notification with restored steps if any
        if (todaySteps > 0) {
            updateNotification(todaySteps)
        }

        scheduleMidnightAlarm(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    /**
     * Persist the latest state before the OS reaps the service after the user
     * swipes the app away from Recents. Without this, any sensor steps
     * accepted in the last debounce window could be lost (Apr 17 OPPO A15
     * "inconsistency after kill" lineage). Also try to relaunch ourselves via
     * an alarm so we recover quickly when the OS allows.
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        try {
            if (bootStepsBaseline != null && lastAcceptedBootSteps >= 0) {
                persistState(lastAcceptedBootSteps)
            }
        } catch (e: Exception) {
            Log.w(TAG, "onTaskRemoved persistState failed: ${e.message}")
        }
        try {
            // Re-arm the midnight alarm in case the system kills us before it
            // would have fired naturally.
            scheduleMidnightAlarm(applicationContext)
        } catch (e: Exception) {
            Log.w(TAG, "onTaskRemoved scheduleMidnightAlarm failed: ${e.message}")
        }
        super.onTaskRemoved(rootIntent)
    }

    /**
     * Wrap the initial [startForeground] in defensive layers so a fresh install
     * on Android 14+ never produces the "app keeps stopping" system dialog
     * the QA team flagged on Apr 27 (Samsung A07 / One UI 7).
     *
     * Failure mode being defended: when the manifest declares
     * `foregroundServiceType="health"`, Android 14+ requires the app to
     * already hold one of {ACTIVITY_RECOGNITION, BODY_SENSORS, health.READ_*}
     * runtime permissions at the moment startForeground runs. On a brand-new
     * install nothing is granted yet and the platform raises
     * `ForegroundServiceTypeNotAllowedException`, which propagates as an
     * unhandled crash on the main thread.
     *
     * The new manifest declares both `health|dataSync` so we have a permission-
     * less fallback; we pick the type at runtime and fall back further to a
     * type-less startForeground if even dataSync is rejected (e.g. OEMs that
     * gate dataSync behind their own background-execution policy).
     */
    private fun startForegroundSafely() {
        val notification = buildNotification(0)

        // Pre-Q: classic two-arg form.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            try {
                startForeground(NOTIFICATION_ID, notification)
            } catch (e: Exception) {
                Log.e(TAG, "startForeground (legacy) failed: ${e.message}")
            }
            return
        }

        val hasActivityRecognition = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACTIVITY_RECOGNITION
        ) == PackageManager.PERMISSION_GRANTED

        val preferredType = if (hasActivityRecognition) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH
        } else {
            // No runtime sensor permission yet — running as dataSync is enough
            // to keep the service alive while we wait for the user to grant
            // ACTIVITY_RECOGNITION through the cubit flow. Once granted, the
            // next process boot will re-enter onCreate with HEALTH.
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        }

        try {
            startForeground(NOTIFICATION_ID, notification, preferredType)
        } catch (e: Exception) {
            Log.w(TAG, "startForeground type=$preferredType failed: ${e.message}, retrying with dataSync")
            try {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                )
            } catch (e2: Exception) {
                Log.e(TAG, "startForeground dataSync fallback failed too: ${e2.message}")
                // Last-resort: type-less call so we at least don't crash. The
                // service may be killed later by the platform but the user
                // never sees the "keeps stopping" dialog.
                try {
                    @Suppress("DEPRECATION")
                    startForeground(NOTIFICATION_ID, notification)
                } catch (e3: Exception) {
                    Log.e(TAG, "startForeground last-resort failed: ${e3.message}")
                }
            }
        }
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null) return

        // TYPE_STEP_DETECTOR fires once per detected step. We use it purely
        // as a cross-check against TYPE_STEP_COUNTER's cumulative number:
        // if COUNTER reports +20 but DETECTOR fired 0 times in the same
        // window, those 20 are almost certainly phantom (sensor drift,
        // vibration in a stationary pocket). Round 4 cross-validation.
        if (event.sensor?.type == Sensor.TYPE_STEP_DETECTOR) {
            synchronized(STATE_LOCK) {
                lastDetectorEventElapsedMs = SystemClock.elapsedRealtime()
                detectorEventsSinceLastCounterAccept++
            }
            return
        }

        if (event.sensor?.type != Sensor.TYPE_STEP_COUNTER) return

        val totalBootSteps = event.values[0].toInt()
        val now = SystemClock.elapsedRealtime()

        // Funnel the WHOLE body through STATE_LOCK so the AlarmManager
        // thread running performMidnightReset / handleTimeOrZoneChange
        // and MethodChannel handlers (setInitialOffset, setSensorFloor,
        // forceUpdateTodaySteps) on the main thread cannot interleave
        // with sensor-thread mutations of bootStepsBaseline, todaySteps,
        // lastAcceptedBootSteps, pendingSteps, initialOffset, or
        // sensorFloor. @Volatile makes individual reads/writes visible
        // across threads but does NOT make compound RMW like
        // `pendingSteps += increment` atomic; under concurrent rotation
        // the just-zeroed pendingSteps would get clobbered with stale-
        // day data and the rate-cap deques (already locked separately)
        // would desync from the scalar state. Java monitor locks are
        // reentrant, so the inner `synchronized(STATE_LOCK)` blocks for
        // the deques nest correctly. Round 3 hardening (audit F5).
        synchronized(STATE_LOCK) {
            onSensorChangedLocked(totalBootSteps, now)
        }
    }

    private fun onSensorChangedLocked(totalBootSteps: Int, now: Long) {
        // Check for day change (handles year rollover too)
        val cal = Calendar.getInstance()
        val currentDay = cal.get(Calendar.DAY_OF_YEAR)
        val currentYear = cal.get(Calendar.YEAR)

        if (currentDay != lastResetDay || currentYear != lastResetYear) {
            // Detect if day went BACKWARD (system time manipulation)
            val isBackward = currentYear < lastResetYear ||
                (currentYear == lastResetYear && currentDay < lastResetDay)

            // Block ANY day change (forward or backward) that arrives faster
            // than MIN_RESET_INTERVAL_MS of monotonic time since the previous
            // reset. Forward used to be unconditionally allowed but that left
            // the trivial "spin the clock forward" attack open (May 26 obs 8
            // + 9 — manual time change re-running the yesterday API + minting
            // fresh reward day). MIN_RESET_INTERVAL_MS=20h covers TZ jumps
            // and unusual schedules while blocking rapid-fire fake rollovers.
            val elapsedSinceReset = now - lastResetElapsedTime
            if (lastResetElapsedTime > 0 && elapsedSinceReset < MIN_RESET_INTERVAL_MS) {
                Log.w(TAG, "Day change rejected on monotonic guard: ${elapsedSinceReset / 1000}s since last reset (need ${MIN_RESET_INTERVAL_MS / 1000}s, isBackward=$isBackward)")
            } else {
                val previousToday = todaySteps
                val rotationDate = String.format(
                    Locale.US,
                    "%04d-%02d-%02d",
                    cal.get(Calendar.YEAR),
                    cal.get(Calendar.MONTH) + 1,
                    cal.get(Calendar.DAY_OF_MONTH)
                )
                dayBeforeSteps = yesterdaySteps
                yesterdaySteps = todaySteps
                bootStepsBaseline = totalBootSteps
                initialOffset = 0
                sensorFloor = 0
                lastResetDay = currentDay
                lastResetYear = currentYear
                lastResetElapsedTime = now
                lastAcceptedBootSteps = totalBootSteps
                pendingSteps = 0
                updatesSincePersist = 0
                synchronized(STATE_LOCK) {
                    recentAcceptedSteps.clear()
                    recentAcceptedTotal = 0
                    hourlyAcceptedSteps.clear()
                    hourlyAcceptedTotal = 0
                }
                todaySteps = 0
                persistState(totalBootSteps)
                // Stamp the rotation so the cubit can detect it on resume even
                // if the LocalBroadcast below is dropped on the floor (Apr 27
                // Bug 2 — process-suspended Flutter side missed events).
                try {
                    getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        .edit()
                        .putString(KEY_LAST_ROTATION_DATE, rotationDate)
                        .putInt(KEY_LAST_ROTATION_PREV_TODAY, previousToday)
                        .apply()
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to stamp rotation: ${e.message}")
                }
                Log.d(TAG, "Day changed: yesterday=$yesterdaySteps, dayBefore=$dayBeforeSteps")
                broadcastSteps(0)
                updateNotification(0)
            }
        }

        // Detect device reboot: if totalBootSteps < last known boot count,
        // the sensor was reset (reboot). Re-baseline.
        if (bootStepsBaseline != null && totalBootSteps < bootStepsBaseline!!) {
            Log.d(TAG, "Reboot detected: totalBoot=$totalBootSteps < baseline=$bootStepsBaseline")
            initialOffset = todaySteps
            sensorFloor = 0
            bootStepsBaseline = totalBootSteps
            lastAcceptedBootSteps = totalBootSteps
            pendingSteps = 0
            // SystemClock.elapsedRealtime() resets on reboot — every entry in
            // the rate-limiter buffers carries a pre-reboot timestamp that
            // is now "in the future" relative to `now`, so the prune loop
            // (which checks `now - entry.first > windowMs`) leaves them in
            // place. recentAcceptedTotal then under-allocates capacity on
            // the post-reboot minute and silently drops legitimate steps.
            // Clear both buffers so the cap starts fresh from the boot we
            // just detected. Round 3 hardening.
            synchronized(STATE_LOCK) {
                recentAcceptedSteps.clear()
                recentAcceptedTotal = 0
                hourlyAcceptedSteps.clear()
                hourlyAcceptedTotal = 0
            }
            // lastAcceptedTime is in-memory only and starts at 0 on cold
            // start. After a reboot detected mid-process (rare — usually
            // the process dies too), it's still holding a pre-reboot
            // elapsedRealtime that is now far in the future relative to
            // `now`, causing the debounce branch to short-return until the
            // wall-clock catches up. Reset so the next event flows normally.
            lastAcceptedTime = 0L
            lastResetElapsedTime = now
            persistState(totalBootSteps)
        }

        if (bootStepsBaseline == null) {
            bootStepsBaseline = totalBootSteps
            lastAcceptedBootSteps = totalBootSteps
            lastResetElapsedTime = now
            persistState(totalBootSteps)
            Log.d(TAG, "Boot baseline set: $totalBootSteps")
        }

        // --- Step debounce: filter micro-vibrations and phantom steps ---
        val incrementSinceLastAccepted = totalBootSteps - lastAcceptedBootSteps
        if (incrementSinceLastAccepted <= 0) return

        // ROUND 4 GATE 1: Vehicle / bicycle suppression. ActivityClassifier
        // flips to true when Play Services' Activity Recognition has
        // detected the user entered a car / bus / bike or is within the
        // 60-second grace window after exiting. Sensor still fires from
        // road vibration in a car or pedal stroke on a bike; counting
        // those events is the single biggest accuracy gap vs Google Fit.
        // We advance bootStepsBaseline by the rejected increment so the
        // discard is permanent — otherwise the next event would re-see
        // these steps in `totalBootSteps - bootStepsBaseline`.
        if (ActivityClassifier.isInVehicleWindow(now)) {
            bootStepsBaseline = (bootStepsBaseline ?: totalBootSteps) + incrementSinceLastAccepted
            lastAcceptedBootSteps = totalBootSteps
            Log.d(
                TAG,
                "Vehicle window: dropping $incrementSinceLastAccepted (totalBoot=$totalBootSteps)"
            )
            return
        }

        // ROUND 4 GATE 2: Step-detector cross-check. TYPE_STEP_DETECTOR
        // fires once per genuinely detected step (vs COUNTER which is
        // cumulative since boot). If COUNTER's delta is meaningfully
        // ahead of how many DETECTOR events fired since the last
        // accepted batch — and the detector is actually available on
        // this device — the COUNTER delta is suspect (sensor drift,
        // vibration without real walking). Discard rather than accept.
        // 0.5x ratio is forgiving: detector occasionally misses on
        // OPPO / cheap-Samsung hardware so we don't demand 1:1.
        if (stepDetectorSensor != null &&
            incrementSinceLastAccepted >= 4 &&
            detectorEventsSinceLastCounterAccept * 2 < incrementSinceLastAccepted
        ) {
            bootStepsBaseline = (bootStepsBaseline ?: totalBootSteps) + incrementSinceLastAccepted
            lastAcceptedBootSteps = totalBootSteps
            Log.d(
                TAG,
                "Detector mismatch: counter+=$incrementSinceLastAccepted but detector fired $detectorEventsSinceLastCounterAccept — likely vibration, dropping"
            )
            detectorEventsSinceLastCounterAccept = 0
            return
        }

        // Accumulate pending steps
        pendingSteps += incrementSinceLastAccepted
        lastAcceptedBootSteps = totalBootSteps
        detectorEventsSinceLastCounterAccept = 0

        // Only accept if enough steps accumulated AND enough time passed
        val timeSinceLastUpdate = now - lastAcceptedTime
        if (pendingSteps < MIN_STEP_INCREMENT && timeSinceLastUpdate < MIN_UPDATE_INTERVAL_MS) {
            return
        }

        // Rate limit: reject physically impossible step rates
        // Don't discard pending steps — let them accumulate and re-evaluate next event
        if (timeSinceLastUpdate > 0 && lastAcceptedTime > 0) {
            val elapsedSeconds = timeSinceLastUpdate / 1000.0
            val stepsPerSecond = pendingSteps / elapsedSeconds
            if (stepsPerSecond > MAX_STEPS_PER_SECOND && elapsedSeconds < 5.0) {
                Log.d(TAG, "Burst deferred: $pendingSteps steps in ${elapsedSeconds}s (${stepsPerSecond}/s)")
                // Don't zero pendingSteps — keep them for next evaluation when rate normalizes
                return
            }
        }

        // Sustained-rate guard: drop steps that would push the trailing-60s
        // total above MAX_STEPS_PER_MINUTE. Unlike the 5s burst guard above,
        // these steps are *discarded* rather than deferred — they represent
        // overcounting drift, not real walking we'll see again next event.
        pruneRecentAccepted(now)
        val minuteCapped = if (recentAcceptedTotal + pendingSteps > MAX_STEPS_PER_MINUTE) {
            val capped = (MAX_STEPS_PER_MINUTE - recentAcceptedTotal).coerceAtLeast(0)
            if (capped < pendingSteps) {
                Log.d(
                    TAG,
                    "Sustained-rate cap (1m): dropping ${pendingSteps - capped} of $pendingSteps " +
                        "(60s total would be ${recentAcceptedTotal + pendingSteps})"
                )
            }
            capped
        } else {
            pendingSteps
        }

        // Hourly cap: layered on top so a sensor that drifts at exactly the
        // per-minute ceiling for an hour straight (which a real walker
        // physically can't sustain) gets clipped before it accumulates into
        // a 9000+ overcount across the day (May 10 QA — 9079 vs G-Fit
        // 4572 without HC for cross-validation).
        pruneHourlyAccepted(now)
        val acceptedNow = if (hourlyAcceptedTotal + minuteCapped > MAX_STEPS_PER_HOUR) {
            val capped = (MAX_STEPS_PER_HOUR - hourlyAcceptedTotal).coerceAtLeast(0)
            if (capped < minuteCapped) {
                Log.d(
                    TAG,
                    "Sustained-rate cap (1h): dropping ${minuteCapped - capped} of $minuteCapped " +
                        "(1h total would be ${hourlyAcceptedTotal + minuteCapped})"
                )
            }
            capped
        } else {
            minuteCapped
        }

        // Discard the rejected portion permanently from the rolling boot delta
        // by advancing the baseline. Without this, todaySteps below would
        // recompute from raw boot deltas and the cap would be a no-op.
        val discarded = pendingSteps - acceptedNow
        if (discarded > 0) {
            bootStepsBaseline = (bootStepsBaseline ?: totalBootSteps) + discarded
        }

        if (acceptedNow <= 0) {
            // Nothing to accept this round; wait for the window to drain.
            pendingSteps = 0
            return
        }

        // ArrayDeque is not thread-safe — funnel all mutations through
        // STATE_LOCK so a midnight-alarm clear can't interleave with a
        // sensor-thread addLast and corrupt the rolling totals (native
        // audit May 28 CRIT-1).
        synchronized(STATE_LOCK) {
            recentAcceptedSteps.addLast(now to acceptedNow)
            recentAcceptedTotal += acceptedNow
            hourlyAcceptedSteps.addLast(now to acceptedNow)
            hourlyAcceptedTotal += acceptedNow
        }

        // Accept the pending steps
        lastAcceptedTime = now
        pendingSteps = 0

        val rawSensorSteps = totalBootSteps - (bootStepsBaseline ?: totalBootSteps)
        todaySteps = rawSensorSteps + initialOffset + sensorFloor

        // Throttle disk writes — persist every N accepted updates
        updatesSincePersist++
        if (updatesSincePersist >= PERSIST_EVERY_N_UPDATES) {
            persistState(totalBootSteps)
            updatesSincePersist = 0
        }

        broadcastSteps(todaySteps)
        updateNotification(todaySteps)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    /** Drop entries older than the trailing 60s window from the rate buffer. */
    private fun pruneRecentAccepted(now: Long) {
        synchronized(STATE_LOCK) {
            while (recentAcceptedSteps.isNotEmpty() &&
                now - recentAcceptedSteps.first().first > ONE_MINUTE_MS
            ) {
                val (_, drop) = recentAcceptedSteps.removeFirst()
                recentAcceptedTotal -= drop
            }
            if (recentAcceptedTotal < 0) recentAcceptedTotal = 0
        }
    }

    /** Drop entries older than the trailing 1h window from the hourly buffer. */
    private fun pruneHourlyAccepted(now: Long) {
        synchronized(STATE_LOCK) {
            while (hourlyAcceptedSteps.isNotEmpty() &&
                now - hourlyAcceptedSteps.first().first > ONE_HOUR_MS
            ) {
                val (_, drop) = hourlyAcceptedSteps.removeFirst()
                hourlyAcceptedTotal -= drop
            }
            if (hourlyAcceptedTotal < 0) hourlyAcceptedTotal = 0
        }
    }

    /** Broadcast step count to Flutter via LocalBroadcastManager. */
    fun broadcastSteps(steps: Int) {
        val updateIntent = Intent(ACTION_STEPS_UPDATE).apply {
            putExtra(EXTRA_STEPS, steps)
        }
        LocalBroadcastManager.getInstance(this).sendBroadcast(updateIntent)
    }

    /** Persist step state to SharedPreferences for cold-start recovery. */
    private fun persistState(currentBootCount: Int) {
        try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().apply {
                putInt(KEY_BOOT_BASELINE, bootStepsBaseline ?: -1)
                putInt(KEY_TODAY_STEPS, todaySteps)
                putInt(KEY_YESTERDAY_STEPS, yesterdaySteps)
                putInt(KEY_DAY_BEFORE_STEPS, dayBeforeSteps)
                putInt(KEY_LAST_RESET_DAY, lastResetDay)
                putInt(KEY_LAST_RESET_YEAR, lastResetYear)
                putInt(KEY_LAST_BOOT_COUNT, currentBootCount)
                apply()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to persist state: ${e.message}")
        }
    }

    /** Restore step state from SharedPreferences on cold start. */
    private fun restoreState() {
        try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            if (!prefs.contains(KEY_LAST_RESET_DAY)) {
                val cal = Calendar.getInstance()
                lastResetDay = cal.get(Calendar.DAY_OF_YEAR)
                lastResetYear = cal.get(Calendar.YEAR)
                lastResetElapsedTime = SystemClock.elapsedRealtime()
                return
            }

            val savedDay = prefs.getInt(KEY_LAST_RESET_DAY, -1)
            val savedYear = prefs.getInt(KEY_LAST_RESET_YEAR, -1)
            val cal = Calendar.getInstance()
            val currentDay = cal.get(Calendar.DAY_OF_YEAR)
            val currentYear = cal.get(Calendar.YEAR)

            // Calculate actual day difference accounting for year boundaries
            val daysDiff = if (savedYear == currentYear) {
                currentDay - savedDay
            } else if (currentYear == savedYear + 1) {
                val savedYearCal = Calendar.getInstance().apply { set(Calendar.YEAR, savedYear) }
                val maxDays = savedYearCal.getActualMaximum(Calendar.DAY_OF_YEAR)
                (maxDays - savedDay) + currentDay
            } else {
                999
            }

            // Capture pre-rotation today so Flutter can recover yesterday when
            // cold-start restore rotates the day (midnight alarm missed because
            // process was dead). Without this stamp, consumeLastRotation() is
            // empty and the UI can keep showing yesterday's total as "today".
            val previousTodayBeforeRestore = prefs.getInt(KEY_TODAY_STEPS, 0)
            val rotationDate = String.format(
                Locale.US,
                "%04d-%02d-%02d",
                cal.get(Calendar.YEAR),
                cal.get(Calendar.MONTH) + 1,
                cal.get(Calendar.DAY_OF_MONTH)
            )

            when {
                daysDiff == 0 -> {
                    // Same day — restore everything
                    val savedBaseline = prefs.getInt(KEY_BOOT_BASELINE, -1)
                    bootStepsBaseline = if (savedBaseline >= 0) savedBaseline else null
                    todaySteps = prefs.getInt(KEY_TODAY_STEPS, 0)
                    yesterdaySteps = prefs.getInt(KEY_YESTERDAY_STEPS, 0)
                    dayBeforeSteps = prefs.getInt(KEY_DAY_BEFORE_STEPS, 0)
                    lastResetDay = savedDay
                    lastResetYear = savedYear
                    lastAcceptedBootSteps = prefs.getInt(KEY_LAST_BOOT_COUNT, -1)
                    Log.d(TAG, "Restored state: today=$todaySteps, baseline=$bootStepsBaseline")
                }
                daysDiff == 1 -> {
                    dayBeforeSteps = prefs.getInt(KEY_YESTERDAY_STEPS, 0)
                    yesterdaySteps = prefs.getInt(KEY_TODAY_STEPS, 0)
                    todaySteps = 0
                    bootStepsBaseline = null
                    initialOffset = 0
                    sensorFloor = 0
                    lastResetDay = currentDay
                    lastResetYear = currentYear
                    lastAcceptedBootSteps = -1
                    stampRestoreRotation(prefs, rotationDate, previousTodayBeforeRestore)
                    Log.d(TAG, "New day restore: yesterday=$yesterdaySteps")
                }
                daysDiff == 2 -> {
                    dayBeforeSteps = prefs.getInt(KEY_TODAY_STEPS, 0)
                    yesterdaySteps = 0
                    todaySteps = 0
                    bootStepsBaseline = null
                    initialOffset = 0
                    sensorFloor = 0
                    lastResetDay = currentDay
                    lastResetYear = currentYear
                    lastAcceptedBootSteps = -1
                    stampRestoreRotation(prefs, rotationDate, previousTodayBeforeRestore)
                    Log.d(TAG, "2-day gap: dayBefore=${dayBeforeSteps}")
                }
                else -> {
                    dayBeforeSteps = 0
                    yesterdaySteps = 0
                    todaySteps = 0
                    bootStepsBaseline = null
                    initialOffset = 0
                    sensorFloor = 0
                    lastResetDay = currentDay
                    lastResetYear = currentYear
                    lastAcceptedBootSteps = -1
                    if (previousTodayBeforeRestore > 0) {
                        stampRestoreRotation(prefs, rotationDate, previousTodayBeforeRestore)
                    }
                    Log.d(TAG, "Stale data cleared, fresh start (${daysDiff}d gap)")
                }
            }

            // Persist rotated counters so a second cold start same day does not
            // re-apply the gap branch with stale KEY_TODAY_STEPS.
            if (daysDiff != 0) {
                try {
                    prefs.edit().apply {
                        putInt(KEY_BOOT_BASELINE, -1)
                        putInt(KEY_TODAY_STEPS, 0)
                        putInt(KEY_YESTERDAY_STEPS, yesterdaySteps)
                        putInt(KEY_DAY_BEFORE_STEPS, dayBeforeSteps)
                        putInt(KEY_LAST_RESET_DAY, currentDay)
                        putInt(KEY_LAST_RESET_YEAR, currentYear)
                        putInt(KEY_LAST_BOOT_COUNT, -1)
                        apply()
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to persist restore rotation: ${e.message}")
                }
            }

            // Set monotonic timestamp on restore
            lastResetElapsedTime = SystemClock.elapsedRealtime()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to restore state: ${e.message}")
            val cal = Calendar.getInstance()
            lastResetDay = cal.get(Calendar.DAY_OF_YEAR)
            lastResetYear = cal.get(Calendar.YEAR)
            lastResetElapsedTime = SystemClock.elapsedRealtime()
        }
    }

    /** Stamp rotation prefs so Flutter drain recovers after cold-start day gap. */
    private fun stampRestoreRotation(
        prefs: SharedPreferences,
        rotationDate: String,
        previousToday: Int,
    ) {
        try {
            prefs.edit()
                .putString(KEY_LAST_ROTATION_DATE, rotationDate)
                .putInt(KEY_LAST_ROTATION_PREV_TODAY, previousToday)
                .apply()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to stamp restore rotation: ${e.message}")
        }
    }

    private fun createNotificationChannel() {
        // NotificationChannel exists only on API 26+. Calling on API 24–25
        // crashes the primary FGS path (legacy FGS already guarded this).
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            "Step Counter",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Step counting service"
            setShowBadge(false)
        }
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.createNotificationChannel(channel)
    }

    private fun buildNotification(steps: Int): Notification {
        // Use a launch intent that's guaranteed to exist post-install. On some
        // devices `getLaunchIntentForPackage` briefly returns null right after
        // a fresh install (Apr 27 Bug 1 audit) — fall back to a no-op intent
        // before letting PendingIntent.getActivity NPE.
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
                setPackage(packageName)
            }

        val pendingIntent = PendingIntent.getActivity(
            this, RC_NOTIFICATION_TAP, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val contentText = if (steps > 0) "$steps steps today" else "Tracking your steps"

        // ic_launcher is shipped at every density; ic_launcher_monochrome was
        // only at xxxhdpi which crashed Resources lookup on lower-density
        // Samsung A07 builds (Apr 27 Bug 1). Stay on the universal asset.
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Step Counter")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_menu_directions)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }

    private var lastNotificationUpdate = 0L
    fun updateNotification(steps: Int) {
        val now = SystemClock.elapsedRealtime()
        // Throttle but always allow steps==0 through so the midnight reset
        // visibly clears the notification (Apr 27 Bug 2 — notification panel
        // showed nothing while UI still held yesterday's count, because the
        // throttle was ignoring the only post-rollover update).
        if (steps != 0 && now - lastNotificationUpdate < 5000) return
        lastNotificationUpdate = now

        try {
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.notify(NOTIFICATION_ID, buildNotification(steps))
        } catch (e: Exception) {
            Log.w(TAG, "updateNotification failed: ${e.message}")
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        // Persist final state before shutting down (only if sensor data was received)
        if (bootStepsBaseline != null && lastAcceptedBootSteps >= 0) {
            persistState(lastAcceptedBootSteps)
        }
        sensorManager?.unregisterListener(this)
        timeChangeReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: Exception) {
                // Receiver may have already been unregistered if service was killed
                Log.w(TAG, "TimeChangeReceiver unregister: ${e.message}")
            }
        }
        timeChangeReceiver = null
        try {
            ActivityClassifier.stopTracking(this)
        } catch (e: Exception) {
            Log.w(TAG, "ActivityClassifier stop failed: ${e.message}")
        }
        isRunning = false
        serviceInstance = null
        super.onDestroy()
    }
}
