package com.example.accurate_step_counter

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import kotlin.math.sqrt

/**
 * Native step detector using Android sensors
 * 
 * Priority:
 * 1. TYPE_STEP_DETECTOR - Best accuracy, hardware-optimized (Android 4.4+)
 * 2. TYPE_ACCELEROMETER - Fallback with software algorithm
 */
class NativeStepDetector(private val context: Context) : SensorEventListener {
    
    companion object {
        private const val TAG = "NativeStepDetector"
        
        // Default config values
        private const val DEFAULT_THRESHOLD = 1.0
        private const val DEFAULT_FILTER_ALPHA = 0.8
        private const val DEFAULT_MIN_TIME_BETWEEN_STEPS_MS = 200
    }
    
    // Callback for step events
    var onStepDetected: ((stepCount: Int) -> Unit)? = null
    
    private var sensorManager: SensorManager? = null
    private var stepDetectorSensor: Sensor? = null
    private var accelerometerSensor: Sensor? = null
    
    private var isUsingStepDetector = false
    private var isRunning = false
    
    // Step counting
    private var stepCount = 0 // Confirmed steps only
    private var pendingStepCount = 0 // Unconfirmed raw detections
    
    // Accelerometer fallback variables
    private var threshold = DEFAULT_THRESHOLD
    private var filterAlpha = DEFAULT_FILTER_ALPHA
    private var minTimeBetweenStepsMs = DEFAULT_MIN_TIME_BETWEEN_STEPS_MS
    
    // Shake rejection configuration
    private val maxStepsPerSecond = 4.0 // Max realistic walking/running rate
    private val validationWindowMs = 1500 // 1.5 second validation window
    private val minPendingSteps = 3 // Minimum steps before confirmation
    
    // Low-pass filter state
    private var filteredX = 0.0
    private var filteredY = 0.0
    private var filteredZ = 0.0
    
    // Peak detection state
    private var previousMagnitude = 0.0
    private var wasAboveThreshold = false
    private var lastStepTime: Long = 0
    
    // Shake rejection state - sliding window validation
    private var windowStartTime: Long = 0
    private var windowStartPendingCount = 0
    private var lastConfirmedPendingCount = 0
    
    init {
        initializeSensors()
    }
    
    private fun initializeSensors() {
        sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        
        // Check if Samsung device - they have known issues with TYPE_STEP_DETECTOR
        val isSamsung = android.os.Build.MANUFACTURER.equals("samsung", ignoreCase = true)
        
        if (isSamsung) {
            android.util.Log.w(TAG, "Samsung device detected - using accelerometer fallback (TYPE_STEP_DETECTOR unreliable on Samsung)")
        }
        
        // Try to get TYPE_STEP_DETECTOR first (more accurate) - but skip on Samsung
        if (!isSamsung) {
            stepDetectorSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)
        }
        
        if (stepDetectorSensor != null) {
            android.util.Log.d(TAG, "TYPE_STEP_DETECTOR available: ${stepDetectorSensor?.name}")
            isUsingStepDetector = true
        } else {
            if (!isSamsung) {
                android.util.Log.w(TAG, "TYPE_STEP_DETECTOR not available, using accelerometer fallback")
            }
            accelerometerSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
            isUsingStepDetector = false
            
            if (accelerometerSensor != null) {
                android.util.Log.d(TAG, "Using TYPE_ACCELEROMETER: ${accelerometerSensor?.name}")
            } else {
                android.util.Log.e(TAG, "No step detection sensors available!")
            }
        }
    }
    
    /**
     * Start step detection
     * 
     * @param config Map with optional configuration:
     *   - threshold: Double (movement threshold for accelerometer)
     *   - filterAlpha: Double (low-pass filter coefficient)
     *   - minTimeBetweenStepsMs: Int (minimum ms between steps)
     */
    fun start(config: Map<String, Any>? = null) {
        if (isRunning) {
            android.util.Log.w(TAG, "Already running")
            return
        }
        
        // Apply configuration
        config?.let {
            threshold = (it["threshold"] as? Double) ?: DEFAULT_THRESHOLD
            filterAlpha = (it["filterAlpha"] as? Double) ?: DEFAULT_FILTER_ALPHA
            minTimeBetweenStepsMs = (it["minTimeBetweenStepsMs"] as? Int) ?: DEFAULT_MIN_TIME_BETWEEN_STEPS_MS
        }
        
        android.util.Log.d(TAG, "Starting with config: threshold=$threshold, filterAlpha=$filterAlpha, minTime=$minTimeBetweenStepsMs")
        
        // Reset state
        resetAccelerometerState()
        
        // Register appropriate sensor
        val sensor = if (isUsingStepDetector) stepDetectorSensor else accelerometerSensor
        
        sensor?.let {
            val registered = sensorManager?.registerListener(
                this,
                it,
                SensorManager.SENSOR_DELAY_GAME  // ~50Hz for better accuracy
            )
            
            if (registered == true) {
                isRunning = true
                android.util.Log.d(TAG, "Sensor listener registered successfully")
            } else {
                android.util.Log.e(TAG, "Failed to register sensor listener")
            }
        } ?: run {
            android.util.Log.e(TAG, "No sensor available to start")
        }
    }
    
    /**
     * Stop step detection
     */
    fun stop() {
        if (!isRunning) {
            return
        }
        
        sensorManager?.unregisterListener(this)
        isRunning = false
        android.util.Log.d(TAG, "Stopped, total steps: $stepCount")
    }
    
    /**
     * Reset step count to zero
     */
    fun reset() {
        stepCount = 0
        resetAccelerometerState()
        android.util.Log.d(TAG, "Step count reset")
    }
    
    /**
     * Get current step count
     */
    fun getStepCount(): Int = stepCount
    
    /**
     * Check if using hardware step detector
     */
    fun isUsingHardwareDetector(): Boolean = isUsingStepDetector
    
    /**
     * Check if running
     */
    fun isActive(): Boolean = isRunning
    
    private fun resetAccelerometerState() {
        filteredX = 0.0
        filteredY = 0.0
        filteredZ = 0.0
        previousMagnitude = 0.0
        wasAboveThreshold = false
        lastStepTime = 0
        // Reset shake rejection state
        pendingStepCount = 0
        windowStartTime = 0
        windowStartPendingCount = 0
        lastConfirmedPendingCount = 0
    }
    
    override fun onSensorChanged(event: SensorEvent?) {
        event ?: return
        
        when (event.sensor.type) {
            Sensor.TYPE_STEP_DETECTOR -> handleStepDetectorEvent(event)
            Sensor.TYPE_ACCELEROMETER -> handleAccelerometerEvent(event)
        }
    }
    
    /**
     * Handle TYPE_STEP_DETECTOR events
     * Each event = 1 step detected by hardware
     */
    private fun handleStepDetectorEvent(event: SensorEvent) {
        stepCount++
        android.util.Log.d(TAG, "Step detected (hardware): $stepCount")
        onStepDetected?.invoke(stepCount)
    }
    
    /**
     * Handle TYPE_ACCELEROMETER events with software step detection and shake rejection
     * 
     * Algorithm:
     * 1. Apply low-pass filter to smooth data
     * 2. Calculate magnitude and detect peaks
     * 3. Track raw detections as "pending" steps
     * 4. Use sliding window validation to confirm steps (shake rejection)
     * 5. Only emit confirmed steps
     */
    private fun handleAccelerometerEvent(event: SensorEvent) {
        val x = event.values[0].toDouble()
        val y = event.values[1].toDouble()
        val z = event.values[2].toDouble()
        val now = System.currentTimeMillis()
        
        // Step 1: Apply low-pass filter
        filteredX = applyLowPassFilter(filteredX, x)
        filteredY = applyLowPassFilter(filteredY, y)
        filteredZ = applyLowPassFilter(filteredZ, z)
        
        // Step 2: Calculate magnitude
        val magnitude = sqrt(filteredX * filteredX + filteredY * filteredY + filteredZ * filteredZ)
        
        // Step 3: Calculate difference from previous
        val diff = magnitude - previousMagnitude
        previousMagnitude = magnitude
        
        // Step 4: Peak detection - upward slope
        if (diff > threshold) {
            wasAboveThreshold = true
        }
        
        // Step 5: Peak detection - downward slope (raw step detected)
        if (diff < 0 && wasAboveThreshold) {
            wasAboveThreshold = false
            
            // Validate minimum time between raw detections
            if (lastStepTime == 0L || (now - lastStepTime) >= minTimeBetweenStepsMs) {
                pendingStepCount++
                lastStepTime = now
                
                // Initialize validation window on first pending step
                if (windowStartTime == 0L) {
                    windowStartTime = now
                    windowStartPendingCount = pendingStepCount - 1
                    android.util.Log.d(TAG, "Shake validation window started")
                }
            }
        }
        
        // Step 6: Sliding window validation for shake rejection
        validateAndConfirmSteps(now)
    }
    
    /**
     * Validate pending steps using sliding window and confirm if rate is reasonable
     */
    private fun validateAndConfirmSteps(now: Long) {
        if (windowStartTime == 0L) return
        
        val windowElapsed = now - windowStartTime
        
        // Wait for validation window to complete
        if (windowElapsed < validationWindowMs) return
        
        // Calculate step rate in this window
        val windowSteps = pendingStepCount - windowStartPendingCount
        val windowSeconds = windowElapsed / 1000.0
        val stepsPerSecond = windowSteps / windowSeconds
        
        if (stepsPerSecond > maxStepsPerSecond) {
            // Rate too high - likely shake, reject all pending steps in this window
            android.util.Log.d(
                TAG,
                "Shake detected: ${String.format("%.2f", stepsPerSecond)}/s > $maxStepsPerSecond/s - rejecting $windowSteps steps"
            )
            
            // Reset window but keep pending count (to track continuous shaking)
            windowStartTime = now
            windowStartPendingCount = pendingStepCount
            return
        }
        
        // Rate is reasonable - check if we have minimum steps to confirm
        if (windowSteps < minPendingSteps) {
            // Not enough steps yet, extend window
            return
        }
        
        // Confirm steps: emit the difference since last confirmation
        val stepsToConfirm = pendingStepCount - lastConfirmedPendingCount
        if (stepsToConfirm > 0) {
            stepCount += stepsToConfirm
            lastConfirmedPendingCount = pendingStepCount
            
            android.util.Log.d(
                TAG,
                "Confirmed $stepsToConfirm steps (rate: ${String.format("%.2f", stepsPerSecond)}/s), total: $stepCount"
            )
            
            // Emit confirmed step event
            onStepDetected?.invoke(stepCount)
        }
        
        // Advance window for continuous walking
        windowStartTime = now
        windowStartPendingCount = pendingStepCount
    }
    
    private fun applyLowPassFilter(previous: Double, current: Double): Double {
        return filterAlpha * previous + (1 - filterAlpha) * current
    }
    
    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        android.util.Log.d(TAG, "Sensor accuracy changed: $accuracy")
    }
    
    /**
     * Clean up resources
     */
    fun dispose() {
        stop()
        onStepDetected = null
    }
}
