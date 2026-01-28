package com.example.accurate_step_counter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.EventChannel

/**
 * Foreground Service for step counting on Android ≤11
 * 
 * This service keeps the step counter running persistently with a notification.
 * Step detection is now done in Dart using sensors_plus, this service only:
 * - Maintains the foreground notification
 * - Holds a wake lock to keep the CPU active
 * - Persists step count to SharedPreferences
 */
class StepCounterForegroundService : Service() {
    
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
        // New keys for proper terminated state sync (stores absolute OS count)
        private const val FOREGROUND_OS_STEP_KEY = "foreground_os_step_count"
        private const val FOREGROUND_START_TIMESTAMP_KEY = "foreground_start_timestamp"
        private const val FOREGROUND_LAST_UPDATE_KEY = "foreground_last_update"
        
        @Volatile
        var isRunning = false
            private set
        
        @Volatile
        var currentStepCount = 0
        
        // EventChannel sink for realtime step events to Flutter
        @Volatile
        var eventSink: EventChannel.EventSink? = null
    }
    
    private var wakeLock: PowerManager.WakeLock? = null
    
    private var sessionStepCount: Int = 0
    private var notificationTitle = "Step Counter"
    private var notificationText = "Tracking your steps..."
    
    override fun onCreate() {
        super.onCreate()
        android.util.Log.d("StepForegroundService", "Service onCreate")
        createNotificationChannel()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        android.util.Log.d("StepForegroundService", "onStartCommand: action=${intent?.action}, isRunning=$isRunning")
        
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START, null -> {
                // Prevent duplicate service starts - if already running, just update notification text if needed
                if (isRunning) {
                    android.util.Log.d("StepForegroundService", "Service already running, ignoring duplicate start")
                    // Still update notification text if provided
                    intent?.getStringExtra(EXTRA_NOTIFICATION_TITLE)?.let { notificationTitle = it }
                    intent?.getStringExtra(EXTRA_NOTIFICATION_TEXT)?.let { notificationText = it }
                    updateNotification()
                    return START_STICKY
                }
                
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
        // On Android 14+ (API 34+), we must explicitly specify the foreground service type
        val notification = createNotification()
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Android 14+ requires explicit service type
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH)
            android.util.Log.d("StepForegroundService", "Started with FOREGROUND_SERVICE_TYPE_HEALTH (Android 14+)")
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10-13: Use the type specified in manifest
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH)
            android.util.Log.d("StepForegroundService", "Started with FOREGROUND_SERVICE_TYPE_HEALTH (Android 10-13)")
        } else {
            // Android 9 and below: No service type required
            startForeground(NOTIFICATION_ID, notification)
            android.util.Log.d("StepForegroundService", "Started without service type (Android 9 and below)")
        }
        
        // Load saved session step count if resuming
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        sessionStepCount = prefs.getInt(FOREGROUND_STEP_COUNT_KEY, 0)
        
        // Save start timestamp if this is a new session
        if (!prefs.contains(FOREGROUND_START_TIMESTAMP_KEY)) {
            prefs.edit().apply {
                putLong(FOREGROUND_START_TIMESTAMP_KEY, System.currentTimeMillis())
                apply()
            }
        }
        
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
    
    private fun stopTracking() {
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
            putLong(TIMESTAMP_KEY, System.currentTimeMillis())
            apply()
        }
        android.util.Log.d("StepForegroundService", "State saved: session=$sessionStepCount")
    }
    
    /**
     * Update step count from Dart layer (sensors_plus based detection)
     * Called via method channel from AccurateStepCounterPlugin
     */
    fun updateStepCount(steps: Int) {
        if (steps > sessionStepCount) {
            sessionStepCount = steps
            currentStepCount = steps
            
            android.util.Log.d("StepForegroundService", "Step count updated from Dart: $sessionStepCount")
            
            // Emit step event via EventChannel to Flutter
            try {
                eventSink?.success(mapOf(
                    "stepCount" to sessionStepCount,
                    "timestamp" to System.currentTimeMillis()
                ))
            } catch (e: Exception) {
                android.util.Log.w("StepForegroundService", "EventChannel emit failed: ${e.message}")
            }
            
            // Update notification periodically (every 10 steps to save battery)
            if (sessionStepCount % 10 == 0) {
                updateNotification()
                saveState()
            }
            
            // Save step count for persistence
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().apply {
                putInt(FOREGROUND_STEP_COUNT_KEY, sessionStepCount)
                putLong(FOREGROUND_LAST_UPDATE_KEY, System.currentTimeMillis())
                apply()
            }
        }
    }
    
    /**
     * Reset the step counter to zero
     */
    fun resetStepCount() {
        sessionStepCount = 0
        currentStepCount = 0

        // Using apply() for async write to prevent ANR
        // Race conditions are handled by in-memory state (sessionStepCount/currentStepCount)
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().apply {
            putInt(FOREGROUND_STEP_COUNT_KEY, 0)
            apply()
        }

        updateNotification()
        android.util.Log.d("StepForegroundService", "Step count reset completed")
    }
}
