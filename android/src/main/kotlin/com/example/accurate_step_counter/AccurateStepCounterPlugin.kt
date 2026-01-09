package com.example.accurate_step_counter

import android.app.Activity
import android.app.Application
import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** Accurate Step Counter Plugin
 *
 * Provides access to Android's OS-level step counter (TYPE_STEP_COUNTER sensor)
 * and SharedPreferences for state persistence across app restarts.
 * 
 * Implements hybrid architecture:
 * - Uses native step detector for foreground/background (realtime)
 * - Auto-starts foreground service when app is terminated on older APIs
 */
class AccurateStepCounterPlugin : FlutterPlugin, MethodCallHandler, SensorEventListener, 
                                   ActivityAware, Application.ActivityLifecycleCallbacks {
    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var context: Context
    private val mainHandler = Handler(Looper.getMainLooper())

    private var sensorManager: SensorManager? = null
    private var stepCounterSensor: Sensor? = null
    private var currentStepCount: Int = 0
    
    // Native step detector
    private var nativeStepDetector: NativeStepDetector? = null
    private var eventSink: EventChannel.EventSink? = null

    // Activity lifecycle tracking for hybrid foreground service
    private var activity: Activity? = null
    private var application: Application? = null
    private var activityCount = 0
    
    // Foreground service configuration (set from Dart layer)
    private var useForegroundServiceOnTerminated = true
    private var foregroundServiceMaxApiLevel = 29  // Default: Android 10
    private var foregroundNotificationTitle = "Step Counter"
    private var foregroundNotificationText = "Tracking your steps..."

    private val PREFS_NAME = "accurate_step_counter_prefs"
    private val STEP_COUNT_KEY = "last_step_count"
    private val TIMESTAMP_KEY = "last_timestamp"

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        android.util.Log.d("AccurateStepCounter", "Plugin attached to Flutter engine")
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "accurate_step_counter")
        channel.setMethodCallHandler(this)
        
        // Setup EventChannel for step events
        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "accurate_step_counter/step_events")
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                android.util.Log.d("AccurateStepCounter", "EventChannel: onListen")
                eventSink = events
            }
            
            override fun onCancel(arguments: Any?) {
                android.util.Log.d("AccurateStepCounter", "EventChannel: onCancel")
                eventSink = null
            }
        })
        
        // Setup EventChannel for foreground service step events (realtime)
        val foregroundEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "accurate_step_counter/foreground_step_events")
        foregroundEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                android.util.Log.d("AccurateStepCounter", "Foreground EventChannel: onListen")
                StepCounterForegroundService.eventSink = events
            }
            
            override fun onCancel(arguments: Any?) {
                android.util.Log.d("AccurateStepCounter", "Foreground EventChannel: onCancel")
                StepCounterForegroundService.eventSink = null
            }
        })
        
        context = flutterPluginBinding.applicationContext
        initializeSensorManager()
        initializeNativeDetector()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        sensorManager?.unregisterListener(this)
        nativeStepDetector?.dispose()
        nativeStepDetector = null
    }
    
    private fun initializeNativeDetector() {
        nativeStepDetector = NativeStepDetector(context)
        nativeStepDetector?.onStepDetected = { stepCount ->
            // Send step events via EventChannel on main thread
            mainHandler.post {
                eventSink?.success(mapOf(
                    "stepCount" to stepCount,
                    "timestamp" to System.currentTimeMillis()
                ))
            }
        }
        android.util.Log.d("AccurateStepCounter", "NativeStepDetector initialized, using hardware: ${nativeStepDetector?.isUsingHardwareDetector()}")
    }

    private fun initializeSensorManager() {
        android.util.Log.d("AccurateStepCounter", "Initializing sensor manager")
        sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        stepCounterSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)

        stepCounterSensor?.let { sensor ->
            android.util.Log.d("AccurateStepCounter", "Step counter sensor found: ${sensor.name}")
            android.util.Log.d("AccurateStepCounter", "Sensor vendor: ${sensor.vendor}, version: ${sensor.version}")
            sensorManager?.registerListener(this, sensor, SensorManager.SENSOR_DELAY_NORMAL)
            android.util.Log.d("AccurateStepCounter", "Sensor listener registered")
        } ?: run {
            android.util.Log.w("AccurateStepCounter", "Step counter sensor NOT available on this device")
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        android.util.Log.d("AccurateStepCounter", "Method called: ${call.method}")

        when (call.method) {
            "initialize" -> {
                android.util.Log.d("AccurateStepCounter", "Initialize method called")
                result.success(true)
            }
            "hasPermission" -> {
                android.util.Log.d("AccurateStepCounter", "hasPermission method called")
                val hasPermission = checkActivityRecognitionPermission()
                result.success(hasPermission)
            }
            "getStepCount" -> {
                android.util.Log.d("AccurateStepCounter", "getStepCount method called")
                val stepCount = getStepCountFromSensor()
                if (stepCount != null) {
                    android.util.Log.d("AccurateStepCounter", "Returning step count: $stepCount")
                    result.success(stepCount)
                } else {
                    android.util.Log.e("AccurateStepCounter", "Step counter sensor not available")
                    result.error("UNAVAILABLE", "Step counter sensor not available", null)
                }
            }
            "saveStepCount" -> {
                val stepCount = call.argument<Int>("stepCount")
                val timestamp = call.argument<Long>("timestamp")
                android.util.Log.d("AccurateStepCounter", "saveStepCount called with: steps=$stepCount, timestamp=$timestamp")
                if (stepCount != null && timestamp != null) {
                    saveStepCountToPrefs(stepCount, timestamp)
                    android.util.Log.d("AccurateStepCounter", "Step count saved successfully")
                    result.success(true)
                } else {
                    android.util.Log.e("AccurateStepCounter", "Invalid arguments for saveStepCount")
                    result.error("INVALID_ARGS", "Invalid arguments", null)
                }
            }
            "getLastStepCount" -> {
                android.util.Log.d("AccurateStepCounter", "getLastStepCount method called")
                val data = getLastStepCountFromPrefs()
                if (data != null) {
                    android.util.Log.d("AccurateStepCounter", "Retrieved last step count: $data")
                    result.success(data)
                } else {
                    android.util.Log.d("AccurateStepCounter", "No previous step count found")
                    result.success(null)
                }
            }
            "syncStepsFromTerminated" -> {
                android.util.Log.d("AccurateStepCounter", "syncStepsFromTerminated method called")
                val syncData = syncStepsFromTerminatedState()
                if (syncData != null) {
                    android.util.Log.d("AccurateStepCounter", "Sync completed successfully: $syncData")
                } else {
                    android.util.Log.d("AccurateStepCounter", "Sync completed with no data to sync")
                }
                result.success(syncData)
            }
            "getAndroidVersion" -> {
                android.util.Log.d("AccurateStepCounter", "getAndroidVersion method called")
                result.success(Build.VERSION.SDK_INT)
            }
            "startForegroundService" -> {
                android.util.Log.d("AccurateStepCounter", "startForegroundService method called")
                val title = call.argument<String>("title") ?: "Step Counter"
                val text = call.argument<String>("text") ?: "Tracking your steps..."
                
                try {
                    val intent = Intent(context, StepCounterForegroundService::class.java).apply {
                        action = StepCounterForegroundService.ACTION_START
                        putExtra(StepCounterForegroundService.EXTRA_NOTIFICATION_TITLE, title)
                        putExtra(StepCounterForegroundService.EXTRA_NOTIFICATION_TEXT, text)
                    }
                    
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(intent)
                    } else {
                        context.startService(intent)
                    }
                    
                    android.util.Log.d("AccurateStepCounter", "Foreground service started successfully")
                    result.success(true)
                } catch (e: Exception) {
                    android.util.Log.e("AccurateStepCounter", "Failed to start foreground service: ${e.message}", e)
                    result.error("SERVICE_ERROR", "Failed to start foreground service: ${e.message}", null)
                }
            }
            "stopForegroundService" -> {
                android.util.Log.d("AccurateStepCounter", "stopForegroundService method called")
                try {
                    val intent = Intent(context, StepCounterForegroundService::class.java).apply {
                        action = StepCounterForegroundService.ACTION_STOP
                    }
                    context.stopService(intent)
                    android.util.Log.d("AccurateStepCounter", "Foreground service stopped successfully")
                    result.success(true)
                } catch (e: Exception) {
                    android.util.Log.e("AccurateStepCounter", "Failed to stop foreground service: ${e.message}", e)
                    result.error("SERVICE_ERROR", "Failed to stop foreground service: ${e.message}", null)
                }
            }
            "isForegroundServiceRunning" -> {
                android.util.Log.d("AccurateStepCounter", "isForegroundServiceRunning method called")
                result.success(StepCounterForegroundService.isRunning)
            }
            "getForegroundStepCount" -> {
                android.util.Log.d("AccurateStepCounter", "getForegroundStepCount method called")
                // Use the maximum of all available step sources:
                // 1. NativeStepDetector (TYPE_STEP_DETECTOR or accelerometer fallback)
                // 2. Foreground service count
                // 3. Main plugin's TYPE_STEP_COUNTER (onSensorChanged updates)
                val nativeCount = nativeStepDetector?.getStepCount() ?: 0
                val foregroundCount = StepCounterForegroundService.currentStepCount
                val pluginCount = currentStepCount  // Main plugin's TYPE_STEP_COUNTER steps
                
                val stepCount = maxOf(nativeCount, foregroundCount, pluginCount)
                android.util.Log.d("AccurateStepCounter", 
                    "Foreground step count: $stepCount (native: $nativeCount, service: $foregroundCount, plugin: $pluginCount)")
                result.success(stepCount)
            }
            "resetForegroundStepCount" -> {
                android.util.Log.d("AccurateStepCounter", "resetForegroundStepCount method called")
                // Reset via SharedPreferences since we can't directly access the service instance
                // Using commit() instead of apply() to ensure synchronous write completes before next read
                // This prevents race conditions on devices with aggressive lifecycle management (MIUI, Samsung)
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                prefs.edit().apply {
                    putInt("foreground_step_count", 0)
                    putInt("foreground_base_step", -1)
                    commit()
                }
                android.util.Log.d("AccurateStepCounter", "Foreground step count reset completed (synchronous)")
                result.success(true)
            }
            // Native step detection methods
            "startNativeDetection" -> {
                android.util.Log.d("AccurateStepCounter", "startNativeDetection method called")
                val threshold = call.argument<Double>("threshold")
                val filterAlpha = call.argument<Double>("filterAlpha")
                val minTimeBetweenStepsMs = call.argument<Int>("minTimeBetweenStepsMs")
                
                val config = mutableMapOf<String, Any>()
                threshold?.let { config["threshold"] = it }
                filterAlpha?.let { config["filterAlpha"] = it }
                minTimeBetweenStepsMs?.let { config["minTimeBetweenStepsMs"] = it }
                
                nativeStepDetector?.start(config)
                result.success(true)
            }
            "stopNativeDetection" -> {
                android.util.Log.d("AccurateStepCounter", "stopNativeDetection method called")
                nativeStepDetector?.stop()
                result.success(true)
            }
            "getNativeStepCount" -> {
                android.util.Log.d("AccurateStepCounter", "getNativeStepCount method called")
                val stepCount = nativeStepDetector?.getStepCount() ?: 0
                result.success(stepCount)
            }
            "resetNativeStepCount" -> {
                android.util.Log.d("AccurateStepCounter", "resetNativeStepCount method called")
                nativeStepDetector?.reset()
                result.success(true)
            }
            "isNativeDetectionActive" -> {
                android.util.Log.d("AccurateStepCounter", "isNativeDetectionActive method called")
                val isActive = nativeStepDetector?.isActive() ?: false
                result.success(isActive)
            }
            "isUsingHardwareDetector" -> {
                android.util.Log.d("AccurateStepCounter", "isUsingHardwareDetector method called")
                val isHardware = nativeStepDetector?.isUsingHardwareDetector() ?: false
                result.success(isHardware)
            }
            // Hybrid foreground service configuration
            "configureForegroundServiceOnTerminated" -> {
                android.util.Log.d("AccurateStepCounter", "configureForegroundServiceOnTerminated method called")
                val enabled = call.argument<Boolean>("enabled") ?: true
                val maxApiLevel = call.argument<Int>("maxApiLevel") ?: 29
                val title = call.argument<String>("title") ?: "Step Counter"
                val text = call.argument<String>("text") ?: "Tracking your steps..."
                
                configureForegroundService(enabled, maxApiLevel, title, text)
                result.success(true)
            }
            "syncStepsFromForegroundService" -> {
                android.util.Log.d("AccurateStepCounter", "syncStepsFromForegroundService method called")
                
                if (!StepCounterForegroundService.isRunning) {
                    android.util.Log.d("AccurateStepCounter", "Foreground service not running")
                    result.success(null)
                    return
                }
                
                val stepCount = StepCounterForegroundService.currentStepCount
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                // Use the foreground service specific keys for proper timestamps
                val startTime = prefs.getLong("foreground_start_timestamp", System.currentTimeMillis())
                val endTime = System.currentTimeMillis()
                
                // Get the last OS step count from foreground service for proper baseline update
                val lastOsStepCount = prefs.getInt("foreground_os_step_count", -1)
                if (lastOsStepCount > 0) {
                    // Update main baseline with correct OS step count (not session count)
                    saveStepCountToPrefs(lastOsStepCount, endTime)
                    android.util.Log.d("AccurateStepCounter", 
                        "Updated baseline from foreground service: $lastOsStepCount")
                }
                
                if (stepCount > 0) {
                    android.util.Log.d("AccurateStepCounter", 
                        "Syncing $stepCount steps from foreground service (${startTime} to ${endTime})")
                    result.success(mapOf(
                        "stepCount" to stepCount,
                        "startTime" to startTime,
                        "endTime" to endTime
                    ))
                } else {
                    result.success(null)
                }
            }
            else -> {
                android.util.Log.w("AccurateStepCounter", "Unknown method called: ${call.method}")
                result.notImplemented()
            }
        }
    }

    private fun getStepCountFromSensor(): Int? {
        android.util.Log.d("StepCounter", "getStepCountFromSensor called, currentStepCount: $currentStepCount")

        // Ensure sensor is registered and try to get fresh data
        if (stepCounterSensor != null && sensorManager != null) {
            // Re-register to trigger an immediate sensor event
            sensorManager?.unregisterListener(this)
            sensorManager?.registerListener(this, stepCounterSensor, SensorManager.SENSOR_DELAY_FASTEST)

            android.util.Log.d("StepCounter", "Sensor re-registered to get fresh data")
        }

        // If we have current data from sensor, return it
        if (currentStepCount > 0) {
            android.util.Log.d("StepCounter", "Returning current step count: $currentStepCount")
            return currentStepCount
        }

        // If currentStepCount is still 0, wait briefly for sensor callback
        // This happens on first app launch or when returning from terminated state
        val maxWaitTime = 1500L // Wait up to 1.5 seconds
        val startTime = System.currentTimeMillis()
        val checkInterval = 50L // Check every 50ms

        while (currentStepCount == 0 && (System.currentTimeMillis() - startTime) < maxWaitTime) {
            try {
                Thread.sleep(checkInterval)
                android.util.Log.d("StepCounter", "Waiting for sensor... currentStepCount: $currentStepCount")
            } catch (e: InterruptedException) {
                android.util.Log.w("StepCounter", "Wait interrupted")
                break
            }
        }

        // If we got data from sensor, return it
        if (currentStepCount > 0) {
            android.util.Log.d("StepCounter", "Got sensor data after waiting: $currentStepCount")
            return currentStepCount
        }

        // If still no sensor data, try to get last known value from prefs
        android.util.Log.w("StepCounter", "No sensor data received, checking prefs")
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val savedCount = prefs.getInt(STEP_COUNT_KEY, -1)

        if (savedCount > 0) {
            android.util.Log.d("StepCounter", "Using saved count from prefs: $savedCount")
            return savedCount
        }

        android.util.Log.e("StepCounter", "No step count available from sensor or prefs")
        return null
    }

    private fun saveStepCountToPrefs(stepCount: Int, timestamp: Long) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().apply {
            putInt(STEP_COUNT_KEY, stepCount)
            putLong(TIMESTAMP_KEY, timestamp)
            apply()
        }
    }

    private fun getLastStepCountFromPrefs(): Map<String, Any>? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val stepCount = prefs.getInt(STEP_COUNT_KEY, -1)
        val timestamp = prefs.getLong(TIMESTAMP_KEY, -1L)

        return if (stepCount > 0 && timestamp > 0) {
            mapOf(
                "stepCount" to stepCount,
                "timestamp" to timestamp
            )
        } else {
            null
        }
    }

    /**
     * Sync steps from terminated state
     * Returns validated step data that was missed while app was closed
     */
    private fun syncStepsFromTerminatedState(): Map<String, Any>? {
        try {
            android.util.Log.d("StepSync", "=== Starting syncStepsFromTerminatedState ===")
            
            // Check if foreground service was running and has data - use its data instead
            // This fixes the Android 11 bug where session count was incorrectly used as baseline
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val foregroundOsCount = prefs.getInt("foreground_os_step_count", -1)
            val foregroundStepCount = prefs.getInt("foreground_step_count", 0)
            val foregroundStartTime = prefs.getLong("foreground_start_timestamp", -1L)
            
            if (foregroundOsCount > 0 && foregroundStepCount > 0 && foregroundStartTime > 0) {
                android.util.Log.d("StepSync", "Found foreground service data:")
                android.util.Log.d("StepSync", "  - OS step count: $foregroundOsCount")
                android.util.Log.d("StepSync", "  - Session steps: $foregroundStepCount")
                android.util.Log.d("StepSync", "  - Start time: $foregroundStartTime")
                
                // Update baseline with correct OS count (not session count!)
                val now = System.currentTimeMillis()
                saveStepCountToPrefs(foregroundOsCount, now)
                
                // Clear foreground service prefs to prevent double-counting
                prefs.edit().apply {
                    remove("foreground_os_step_count")
                    remove("foreground_step_count")
                    remove("foreground_start_timestamp")
                    remove("foreground_last_update")
                    apply()
                }
                android.util.Log.d("StepSync", "Cleared foreground service data, returning $foregroundStepCount steps")
                
                // Return the session steps from foreground service (the actual walked steps)
                return mapOf(
                    "missedSteps" to foregroundStepCount,
                    "startTime" to foregroundStartTime,
                    "endTime" to now
                )
            }

            // No foreground service data - use standard TYPE_STEP_COUNTER sync (Android 12+ path)
            android.util.Log.d("StepSync", "No foreground service data, using TYPE_STEP_COUNTER sync")
            
            // Get current OS-level step count
            val currentStepCount = getStepCountFromSensor()
            android.util.Log.d("StepSync", "Current OS step count: $currentStepCount")

            if (currentStepCount == null || currentStepCount <= 0) {
                android.util.Log.w("StepSync", "No current step count available from sensor")
                return null
            }

            // Get last saved step data
            val lastSavedData = getLastStepCountFromPrefs()
            if (lastSavedData == null) {
                android.util.Log.d("StepSync", "No previous step data found - this is the first run after install")
                // First time - save current state and return null (no missed steps)
                val now = System.currentTimeMillis()
                saveStepCountToPrefs(currentStepCount, now)
                android.util.Log.d("StepSync", "Saved baseline: $currentStepCount steps at $now")
                return null
            }

            val lastStepCount = lastSavedData["stepCount"] as Int
            val lastTimestamp = lastSavedData["timestamp"] as Long

            android.util.Log.d("StepSync", "Last saved step count: $lastStepCount at timestamp: $lastTimestamp")

            // Calculate missed steps
            val missedSteps = currentStepCount - lastStepCount
            val currentTime = System.currentTimeMillis()
            val elapsedTimeMs = currentTime - lastTimestamp
            val elapsedMinutes = elapsedTimeMs / (1000.0 * 60.0)

            android.util.Log.d("StepSync", "Calculated: $missedSteps missed steps over ${elapsedMinutes.toInt()} minutes")

            // Validation 1: Check if missed steps is positive
            if (missedSteps <= 0) {
                android.util.Log.d("StepSync", "No new steps detected (missedSteps: $missedSteps) - possible device reboot")
                // Save current state anyway
                saveStepCountToPrefs(currentStepCount, currentTime)
                return null
            }

            // Validation 2: Check if elapsed time is reasonable (not negative, not from future)
            if (elapsedTimeMs < 0) {
                android.util.Log.w("StepSync", "Invalid timestamp - time went backwards (elapsed: $elapsedTimeMs ms)")
                saveStepCountToPrefs(currentStepCount, currentTime)
                return null
            }

            // Validation 3: Check if missed steps is reasonable (not more than 50,000)
            val MAX_REASONABLE_STEPS = 50000
            if (missedSteps > MAX_REASONABLE_STEPS) {
                android.util.Log.w("StepSync", "Missed steps ($missedSteps) exceeds reasonable limit ($MAX_REASONABLE_STEPS)")
                // Probably a sensor reset - save current state and return null
                saveStepCountToPrefs(currentStepCount, currentTime)
                return null
            }

            // Validation 4: Check if step rate is reasonable (max 3 steps per second)
            val elapsedSeconds = elapsedTimeMs / 1000.0
            if (elapsedSeconds > 0) {
                val stepsPerSecond = missedSteps / elapsedSeconds
                android.util.Log.d("StepSync", "Step rate: ${"%.3f".format(stepsPerSecond)} steps/second")

                if (stepsPerSecond > 3.0) {
                    android.util.Log.w("StepSync", "Step rate (${"%.3f".format(stepsPerSecond)} steps/sec) is unreasonably high (max: 3.0)")
                    saveStepCountToPrefs(currentStepCount, currentTime)
                    return null
                }
            }

            // All validations passed - return the missed steps data
            android.util.Log.d("StepSync", "✓ All validations passed!")
            android.util.Log.d("StepSync", "Syncing $missedSteps steps from terminated state")
            android.util.Log.d("StepSync", "Time range: $lastTimestamp to $currentTime")

            // Save current state
            saveStepCountToPrefs(currentStepCount, currentTime)

            // Return data for the application
            return mapOf(
                "missedSteps" to missedSteps,
                "startTime" to lastTimestamp,
                "endTime" to currentTime
            )

        } catch (e: Exception) {
            android.util.Log.e("StepSync", "Error syncing steps: ${e.message}", e)
            return null
        }
    }

    /**
     * Check if ACTIVITY_RECOGNITION permission is granted
     *
     * For Android 10+ (API 29+), this permission is required to access step counter sensor
     * For lower versions, this permission is not required
     */
    private fun checkActivityRecognitionPermission(): Boolean {
        // Only needed on Android 10+ (API 29+)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            android.util.Log.d("AccurateStepCounter", "Permission not required for Android < 10")
            return true
        }

        val permission = Manifest.permission.ACTIVITY_RECOGNITION
        val granted = ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

        android.util.Log.d("AccurateStepCounter", "ACTIVITY_RECOGNITION permission granted: $granted")
        return granted
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type == Sensor.TYPE_STEP_COUNTER) {
            // TYPE_STEP_COUNTER returns the total steps since last reboot
            val newCount = event.values[0].toInt()
            android.util.Log.d("StepCounter", "onSensorChanged: Sensor reported $newCount steps (previous: $currentStepCount)")
            currentStepCount = newCount
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // Not needed for step counter
    }

    // ============================================================
    // ActivityAware Implementation - Hybrid foreground service
    // ============================================================

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        android.util.Log.d("AccurateStepCounter", "onAttachedToActivity")
        activity = binding.activity
        
        // Register lifecycle callbacks
        application = binding.activity.application
        application?.registerActivityLifecycleCallbacks(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        android.util.Log.d("AccurateStepCounter", "onDetachedFromActivityForConfigChanges")
        // Don't unregister - config change, activity will be reattached
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        android.util.Log.d("AccurateStepCounter", "onReattachedToActivityForConfigChanges")
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        android.util.Log.d("AccurateStepCounter", "onDetachedFromActivity")
        application?.unregisterActivityLifecycleCallbacks(this)
        activity = null
        application = null
    }

    // ============================================================
    // ActivityLifecycleCallbacks - Track activity count
    // ============================================================

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
        // Not used
    }

    override fun onActivityStarted(activity: Activity) {
        activityCount++
        android.util.Log.d("AccurateStepCounter", "Activity started, count: $activityCount")
        
        // If coming back from terminated state, check if foreground service was running
        if (activityCount == 1 && StepCounterForegroundService.isRunning) {
            android.util.Log.d("AccurateStepCounter", "App resumed from terminated - foreground service was running")
            // Steps will be synced via syncStepsFromForegroundService call from Dart
        }
    }

    override fun onActivityResumed(activity: Activity) {
        // Not used
    }

    override fun onActivityPaused(activity: Activity) {
        // Not used
    }

    override fun onActivityStopped(activity: Activity) {
        activityCount--
        android.util.Log.d("AccurateStepCounter", "Activity stopped, count: $activityCount")
        
        // When all activities are stopped and this looks like app termination
        // Start foreground service on older APIs for continued step counting
        if (activityCount == 0 && shouldStartForegroundServiceOnTermination()) {
            android.util.Log.d("AccurateStepCounter", "All activities stopped - starting foreground service for terminated state tracking")
            startForegroundServiceForTerminatedState()
        }
    }

    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {
        // Not used
    }

    override fun onActivityDestroyed(activity: Activity) {
        // Not used
    }

    // ============================================================
    // Helper methods for hybrid foreground service
    // ============================================================

    /**
     * Check if we should start foreground service when app is being terminated
     */
    private fun shouldStartForegroundServiceOnTermination(): Boolean {
        if (!useForegroundServiceOnTerminated) {
            android.util.Log.d("AccurateStepCounter", "Foreground service disabled by config")
            return false
        }
        
        if (Build.VERSION.SDK_INT > foregroundServiceMaxApiLevel) {
            android.util.Log.d("AccurateStepCounter", 
                "API ${Build.VERSION.SDK_INT} > $foregroundServiceMaxApiLevel, using TYPE_STEP_COUNTER sync instead")
            return false
        }
        
        if (StepCounterForegroundService.isRunning) {
            android.util.Log.d("AccurateStepCounter", "Foreground service already running")
            return false
        }
        
        return true
    }

    /**
     * Start foreground service when app is terminated on older APIs
     */
    private fun startForegroundServiceForTerminatedState() {
        try {
            // Save current step count before starting foreground service
            saveCurrentStepCount()
            
            val intent = Intent(context, StepCounterForegroundService::class.java).apply {
                action = StepCounterForegroundService.ACTION_START
                putExtra(StepCounterForegroundService.EXTRA_NOTIFICATION_TITLE, foregroundNotificationTitle)
                putExtra(StepCounterForegroundService.EXTRA_NOTIFICATION_TEXT, foregroundNotificationText)
            }
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            
            android.util.Log.d("AccurateStepCounter", "Foreground service started for terminated state")
        } catch (e: Exception) {
            android.util.Log.e("AccurateStepCounter", "Failed to start foreground service: ${e.message}", e)
        }
    }

    /**
     * Save current OS step count before termination for later sync
     */
    private fun saveCurrentStepCount() {
        if (currentStepCount > 0) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().apply {
                putInt(STEP_COUNT_KEY, currentStepCount)
                putLong(TIMESTAMP_KEY, System.currentTimeMillis())
                apply()
            }
            android.util.Log.d("AccurateStepCounter", "Saved step count: $currentStepCount before termination")
        }
    }

    /**
     * Configure foreground service settings from Dart layer
     */
    fun configureForegroundService(
        enabled: Boolean,
        maxApiLevel: Int,
        title: String,
        text: String
    ) {
        useForegroundServiceOnTerminated = enabled
        foregroundServiceMaxApiLevel = maxApiLevel
        foregroundNotificationTitle = title
        foregroundNotificationText = text
        android.util.Log.d("AccurateStepCounter", 
            "Foreground service configured: enabled=$enabled, maxApi=$maxApiLevel")
    }
}
