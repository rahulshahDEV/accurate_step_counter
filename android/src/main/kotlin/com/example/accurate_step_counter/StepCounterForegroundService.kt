package com.example.accurate_step_counter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * Foreground Service for step counting on Android ≤10
 * 
 * This service keeps the step counter running persistently with a notification.
 * It's needed because on Android 10 and below, the OS may not reliably 
 * continue counting steps when the app is terminated.
 */
class StepCounterForegroundService : Service(), SensorEventListener {
    
    companion object {
        const val CHANNEL_ID = "step_counter_channel"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "com.example.accurate_step_counter.START"
        const val ACTION_STOP = "com.example.accurate_step_counter.STOP"
        const val EXTRA_NOTIFICATION_TITLE = "notification_title"
        const val EXTRA_NOTIFICATION_TEXT = "notification_text"
        
        private const val PREFS_NAME = "accurate_step_counter_prefs"
        private const val STEP_COUNT_KEY = "last_step_count"
        private const val TIMESTAMP_KEY = "last_timestamp"
        private const val FOREGROUND_STEP_COUNT_KEY = "foreground_step_count"
        private const val FOREGROUND_BASE_STEP_KEY = "foreground_base_step"
        
        @Volatile
        var isRunning = false
            private set
        
        @Volatile
        var currentStepCount = 0
            private set
    }
    
    private var sensorManager: SensorManager? = null
    private var stepCounterSensor: Sensor? = null
    private var wakeLock: PowerManager.WakeLock? = null
    
    private var baseStepCount: Int = -1
    private var sessionStepCount: Int = 0
    private var notificationTitle = "Step Counter"
    private var notificationText = "Tracking your steps..."
    
    override fun onCreate() {
        super.onCreate()
        android.util.Log.d("StepForegroundService", "Service onCreate")
        createNotificationChannel()
        initializeSensorManager()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        android.util.Log.d("StepForegroundService", "onStartCommand: action=${intent?.action}")
        
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START, null -> {
                // Get custom notification text if provided
                notificationTitle = intent?.getStringExtra(EXTRA_NOTIFICATION_TITLE) 
                    ?: "Step Counter"
                notificationText = intent?.getStringExtra(EXTRA_NOTIFICATION_TEXT) 
                    ?: "Tracking your steps..."
                
                startForegroundService()
            }
        }
        
        return START_STICKY
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    override fun onDestroy() {
        android.util.Log.d("StepForegroundService", "Service onDestroy")
        stopTracking()
        super.onDestroy()
    }
    
    private fun startForegroundService() {
        android.util.Log.d("StepForegroundService", "Starting foreground service")
        
        // Acquire wake lock to prevent CPU from sleeping
        acquireWakeLock()
        
        // Start as foreground service with notification
        val notification = createNotification()
        startForeground(NOTIFICATION_ID, notification)
        
        // Start sensor listening
        startTracking()
        
        isRunning = true
        android.util.Log.d("StepForegroundService", "Foreground service started successfully")
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Step Counter",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows when step counting is active"
                setShowBadge(false)
            }
            
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager?.createNotificationChannel(channel)
            android.util.Log.d("StepForegroundService", "Notification channel created")
        }
    }
    
    private fun createNotification(): Notification {
        // Create intent to open the app when notification is tapped
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
        
        // Create stop action
        val stopIntent = Intent(this, StepCounterForegroundService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            0,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(notificationTitle)
            .setContentText("$notificationText ($sessionStepCount steps)")
            .setSmallIcon(android.R.drawable.ic_menu_directions)
            .setContentIntent(pendingIntent)
            .addAction(android.R.drawable.ic_media_pause, "Stop", stopPendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }
    
    private fun updateNotification() {
        val notification = createNotification()
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager?.notify(NOTIFICATION_ID, notification)
    }
    
    private fun initializeSensorManager() {
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        stepCounterSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        
        if (stepCounterSensor != null) {
            android.util.Log.d("StepForegroundService", "Step counter sensor found: ${stepCounterSensor?.name}")
        } else {
            android.util.Log.w("StepForegroundService", "Step counter sensor NOT available")
        }
    }
    
    private fun startTracking() {
        stepCounterSensor?.let { sensor ->
            sensorManager?.registerListener(
                this,
                sensor,
                SensorManager.SENSOR_DELAY_NORMAL
            )
            android.util.Log.d("StepForegroundService", "Sensor listener registered")
        }
        
        // Load saved session step count if resuming
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        sessionStepCount = prefs.getInt(FOREGROUND_STEP_COUNT_KEY, 0)
        baseStepCount = prefs.getInt(FOREGROUND_BASE_STEP_KEY, -1)
        
        android.util.Log.d("StepForegroundService", "Tracking started with session: $sessionStepCount, base: $baseStepCount")
    }
    
    private fun stopTracking() {
        sensorManager?.unregisterListener(this)
        releaseWakeLock()
        
        // Save current state
        saveState()
        
        isRunning = false
        currentStepCount = 0
        android.util.Log.d("StepForegroundService", "Tracking stopped")
    }
    
    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "AccurateStepCounter::StepCounterWakeLock"
            ).apply {
                acquire(10 * 60 * 60 * 1000L) // 10 hours max
            }
            android.util.Log.d("StepForegroundService", "Wake lock acquired")
        }
    }
    
    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
                android.util.Log.d("StepForegroundService", "Wake lock released")
            }
        }
        wakeLock = null
    }
    
    private fun saveState() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().apply {
            putInt(FOREGROUND_STEP_COUNT_KEY, sessionStepCount)
            putInt(FOREGROUND_BASE_STEP_KEY, baseStepCount)
            putLong(TIMESTAMP_KEY, System.currentTimeMillis())
            apply()
        }
        android.util.Log.d("StepForegroundService", "State saved: session=$sessionStepCount, base=$baseStepCount")
    }
    
    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type == Sensor.TYPE_STEP_COUNTER) {
            val totalSteps = event.values[0].toInt()
            
            // First reading - set as baseline
            if (baseStepCount < 0) {
                baseStepCount = totalSteps
                android.util.Log.d("StepForegroundService", "Baseline set: $baseStepCount")
                return
            }
            
            // Calculate steps since service started
            val stepsFromSensor = totalSteps - baseStepCount
            
            // Only update if steps increased
            if (stepsFromSensor > sessionStepCount) {
                sessionStepCount = stepsFromSensor
                currentStepCount = sessionStepCount
                
                android.util.Log.d("StepForegroundService", "Step detected! Total: $sessionStepCount")
                
                // Update notification periodically (every 10 steps to save battery)
                if (sessionStepCount % 10 == 0) {
                    updateNotification()
                    saveState()
                }
                
                // Send step count via shared preferences for Flutter to read
                val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                prefs.edit().putInt(STEP_COUNT_KEY, sessionStepCount).apply()
            }
        }
    }
    
    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        android.util.Log.d("StepForegroundService", "Sensor accuracy changed: $accuracy")
    }
    
    /**
     * Reset the step counter to zero
     */
    fun resetStepCount() {
        sessionStepCount = 0
        baseStepCount = -1
        currentStepCount = 0
        
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().apply {
            putInt(FOREGROUND_STEP_COUNT_KEY, 0)
            putInt(FOREGROUND_BASE_STEP_KEY, -1)
            apply()
        }
        
        updateNotification()
        android.util.Log.d("StepForegroundService", "Step count reset")
    }
}
