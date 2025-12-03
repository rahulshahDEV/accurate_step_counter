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
        sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        stepCounterSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)

        stepCounterSensor?.let { sensor ->
            sensorManager?.registerListener(this, sensor, SensorManager.SENSOR_DELAY_NORMAL)
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initialize" -> {
                result.success(true)
            }
            "getStepCount" -> {
                val stepCount = getStepCountFromSensor()
                if (stepCount != null) {
                    result.success(stepCount)
                } else {
                    result.error("UNAVAILABLE", "Step counter sensor not available", null)
                }
            }
            "saveStepCount" -> {
                val stepCount = call.argument<Int>("stepCount")
                val timestamp = call.argument<Long>("timestamp")
                if (stepCount != null && timestamp != null) {
                    saveStepCountToPrefs(stepCount, timestamp)
                    result.success(true)
                } else {
                    result.error("INVALID_ARGS", "Invalid arguments", null)
                }
            }
            "getLastStepCount" -> {
                val data = getLastStepCountFromPrefs()
                if (data != null) {
                    result.success(data)
                } else {
                    result.success(null)
                }
            }
            "syncStepsFromTerminated" -> {
                val syncData = syncStepsFromTerminatedState()
                result.success(syncData)
            }
            else -> {
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
            val currentStepCount = getStepCountFromSensor()
            if (currentStepCount == null || currentStepCount <= 0) {
                android.util.Log.d("StepSync", "No current step count available")
                return null
            }

            val lastSavedData = getLastStepCountFromPrefs()
            if (lastSavedData == null) {
                android.util.Log.d("StepSync", "No previous step data found - first run")
                val now = System.currentTimeMillis()
                saveStepCountToPrefs(currentStepCount, now)
                return null
            }

            val lastStepCount = lastSavedData["stepCount"] as Int
            val lastTimestamp = lastSavedData["timestamp"] as Long
            val missedSteps = currentStepCount - lastStepCount
            val currentTime = System.currentTimeMillis()
            val elapsedTimeMs = currentTime - lastTimestamp

            // Validation 1: Check if missed steps is positive
            if (missedSteps <= 0) {
                android.util.Log.d("StepSync", "No new steps or sensor reset detected")
                saveStepCountToPrefs(currentStepCount, currentTime)
                return null
            }

            // Validation 2: Check if elapsed time is reasonable
            if (elapsedTimeMs < 0) {
                android.util.Log.w("StepSync", "Invalid timestamp - time went backwards")
                saveStepCountToPrefs(currentStepCount, currentTime)
                return null
            }

            // Validation 3: Check if missed steps is reasonable (not more than 50,000)
            val MAX_REASONABLE_STEPS = 50000
            if (missedSteps > MAX_REASONABLE_STEPS) {
                android.util.Log.w("StepSync", "Missed steps ($missedSteps) exceeds reasonable limit")
                saveStepCountToPrefs(currentStepCount, currentTime)
                return null
            }

            // Validation 4: Check if step rate is reasonable (max 3 steps per second)
            val elapsedSeconds = elapsedTimeMs / 1000.0
            if (elapsedSeconds > 0) {
                val stepsPerSecond = missedSteps / elapsedSeconds
                if (stepsPerSecond > 3.0) {
                    android.util.Log.w("StepSync", "Step rate ($stepsPerSecond steps/sec) is unreasonably high")
                    saveStepCountToPrefs(currentStepCount, currentTime)
                    return null
                }
            }

            // All validations passed
            android.util.Log.d("StepSync", "Syncing $missedSteps steps from terminated state")
            saveStepCountToPrefs(currentStepCount, currentTime)

            return mapOf(
                "missedSteps" to missedSteps,
                "startTime" to lastTimestamp,
                "endTime" to currentTime
            )

        } catch (e: Exception) {
            android.util.Log.e("StepSync", "Error syncing steps: ${e.message}")
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
