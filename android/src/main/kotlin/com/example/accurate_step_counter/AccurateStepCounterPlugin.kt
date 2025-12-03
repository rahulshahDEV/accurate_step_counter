package com.example.accurate_step_counter

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** Accurate Step Counter Plugin
 *
 * Provides access to Android's OS-level step counter (TYPE_STEP_COUNTER sensor)
 * and SharedPreferences for state persistence across app restarts.
 */
class AccurateStepCounterPlugin : FlutterPlugin, MethodCallHandler, SensorEventListener {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    private var sensorManager: SensorManager? = null
    private var stepCounterSensor: Sensor? = null
    private var currentStepCount: Int = 0

    private val PREFS_NAME = "accurate_step_counter_prefs"
    private val STEP_COUNT_KEY = "last_step_count"
    private val TIMESTAMP_KEY = "last_timestamp"

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        android.util.Log.d("AccurateStepCounter", "Plugin attached to Flutter engine")
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "accurate_step_counter")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
        initializeSensorManager()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        sensorManager?.unregisterListener(this)
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
}
