package com.example.accurate_step_counter

import android.app.AlarmManager
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
import android.os.IBinder
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import java.util.Calendar

class StepCounterService : Service(), SensorEventListener {
    companion object {
        const val TAG = "StepCounterService"
        const val CHANNEL_ID = "native_step_counter_channel"
        const val NOTIFICATION_ID = 2001
        const val ACTION_STEPS_UPDATE = "com.example.accurate_step_counter.STEPS_UPDATE"
        const val EXTRA_STEPS = "steps"

        private var initialOffset = 0
        private var sensorFloor = 0
        private var bootStepsBaseline: Int? = null
        private var todaySteps = 0
        private var yesterdaySteps = 0
        private var dayBeforeSteps = 0
        private var lastResetDay = -1
        private var isRunning = false

        fun isServiceRunning(): Boolean = isRunning

        fun getTodaySteps(): Int = todaySteps
        fun getYesterdaySteps(): Int = yesterdaySteps
        fun getDayBeforeSteps(): Int = dayBeforeSteps

        fun setInitialOffset(offset: Int) {
            initialOffset = offset
            Log.d(TAG, "Initial offset set to $offset")
        }

        fun setSensorFloor(floor: Int) {
            sensorFloor = floor
            Log.d(TAG, "Sensor floor set to $floor")
        }

        fun needsCalibration(): Boolean {
            return bootStepsBaseline == null || todaySteps == 0
        }
    }

    private var sensorManager: SensorManager? = null
    private var stepSensor: Sensor? = null
    private var midnightAlarmSet = false
    private var lastNotificationUpdate = 0L

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification(0))

        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        stepSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)

        lastResetDay = Calendar.getInstance().get(Calendar.DAY_OF_YEAR)

        stepSensor?.let {
            sensorManager?.registerListener(this, it, SensorManager.SENSOR_DELAY_UI)
            isRunning = true
            Log.d(TAG, "Step sensor registered")
        } ?: run {
            Log.e(TAG, "No TYPE_STEP_COUNTER sensor found")
            stopSelf()
        }

        scheduleMidnightReset()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type != Sensor.TYPE_STEP_COUNTER) return

        val totalBootSteps = event.values[0].toInt()

        val today = Calendar.getInstance().get(Calendar.DAY_OF_YEAR)
        if (today != lastResetDay) {
            dayBeforeSteps = yesterdaySteps
            yesterdaySteps = todaySteps
            bootStepsBaseline = totalBootSteps
            initialOffset = 0
            sensorFloor = 0
            lastResetDay = today
            Log.d(TAG, "Day changed: yesterday=$yesterdaySteps, dayBefore=$dayBeforeSteps")
        }

        if (bootStepsBaseline == null) {
            bootStepsBaseline = totalBootSteps
            Log.d(TAG, "Boot baseline set: $totalBootSteps")
        }

        val rawSensorSteps = totalBootSteps - (bootStepsBaseline ?: totalBootSteps)
        todaySteps = rawSensorSteps + initialOffset + sensorFloor

        val updateIntent = Intent(ACTION_STEPS_UPDATE).apply {
            putExtra(EXTRA_STEPS, todaySteps)
        }
        LocalBroadcastManager.getInstance(this).sendBroadcast(updateIntent)

        updateNotification(todaySteps)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // no-op
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Accurate Step Counter",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Tracks your hardware step counter"
            setShowBadge(false)
        }

        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager?.createNotificationChannel(channel)
    }

    private fun buildNotification(steps: Int): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Step Counter")
            .setContentText("Tracking steps: $steps")
            .setSmallIcon(android.R.drawable.ic_menu_directions)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }

    private fun updateNotification(steps: Int) {
        val now = SystemClock.elapsedRealtime()
        if (now - lastNotificationUpdate < 5000) return

        lastNotificationUpdate = now
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager?.notify(NOTIFICATION_ID, buildNotification(steps))
    }

    private fun scheduleMidnightReset() {
        if (midnightAlarmSet) return

        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, MidnightReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val midnight = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            add(Calendar.DAY_OF_YEAR, 1)
        }

        alarmManager.setRepeating(
            AlarmManager.RTC_WAKEUP,
            midnight.timeInMillis,
            AlarmManager.INTERVAL_DAY,
            pendingIntent
        )

        midnightAlarmSet = true
        Log.d(TAG, "Midnight alarm scheduled")
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        sensorManager?.unregisterListener(this)
        isRunning = false
        super.onDestroy()
    }
}
