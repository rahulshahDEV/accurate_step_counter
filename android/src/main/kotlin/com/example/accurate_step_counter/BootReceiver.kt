package com.example.accurate_step_counter

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Re-launches [StepCounterService] after the device finishes booting so the
 * foreground step counter and the midnight rollover alarm pick up right where
 * they left off without the user needing to re-open the app.
 *
 * Why this matters for the QA scenarios we've been chasing: the OPPO A15 /
 * Samsung A07 midnight-reset bugs assume the foreground service is alive at
 * midnight to receive the alarm. If the user reboots in the evening and
 * doesn't re-open the host app before midnight, without this receiver the
 * `MidnightReceiver` PendingIntent stays registered but `serviceInstance`
 * is null, so the rotation stamp is the only thing that fires — and the next
 * cubit-side drain happens whenever the user gets around to opening the app.
 * Booting back into the service closes that hole.
 *
 * Guarded by ACTIVITY_RECOGNITION because the manifest's
 * `foregroundServiceType="health"` requires that runtime permission to be
 * granted before `startForegroundService` (Android 14+ rule we fought on
 * Apr 27). If the user uninstalled+reinstalled without re-granting, we
 * silently skip — the next app open will run the normal permission flow.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        val ctx = context ?: return
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_LOCKED_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON" &&
            action != "com.htc.intent.action.QUICKBOOT_POWERON"
        ) {
            return
        }

        // Re-arm the midnight alarm regardless of whether we can (re)start the
        // foreground service — even a sensorless device benefits from the
        // alarm firing the rotation stamp at midnight.
        try {
            StepCounterService.scheduleMidnightAlarm(ctx)
        } catch (e: Exception) {
            Log.w("BootReceiver", "scheduleMidnightAlarm post-boot failed: ${e.message}")
        }

        // Only the regular BOOT_COMPLETED is on the foreground-service start
        // allow-list on modern Android. LOCKED_BOOT_COMPLETED fires pre-
        // user-unlock so credential-encrypted storage isn't readable and
        // health-type FG service start is denied; QUICKBOOT_POWERON isn't on
        // the boot allow-list at all on stock Android (native audit May 28
        // CRIT-2). For those two actions we still benefit from re-arming
        // the midnight alarm (already done above) but we don't try to start
        // the foreground service — the next normal user interaction will.
        if (action != Intent.ACTION_BOOT_COMPLETED) {
            Log.d("BootReceiver", "Skipping FG-service start for action=$action (alarm rescheduled)")
            return
        }

        // ACTIVITY_RECOGNITION gate mirrors the MainActivity start path.
        val needsAr = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
        val arGranted = if (needsAr) {
            ContextCompat.checkSelfPermission(
                ctx,
                Manifest.permission.ACTIVITY_RECOGNITION
            ) == PackageManager.PERMISSION_GRANTED
        } else true
        if (!arGranted) {
            Log.d(
                "BootReceiver",
                "Skipping service restart post-boot: ACTIVITY_RECOGNITION not granted"
            )
            return
        }

        try {
            val serviceIntent = Intent(ctx, StepCounterService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ctx.startForegroundService(serviceIntent)
            } else {
                ctx.startService(serviceIntent)
            }
            Log.d("BootReceiver", "StepCounterService re-started post-boot ($action)")
        } catch (e: Exception) {
            Log.e("BootReceiver", "Failed to restart StepCounterService post-boot: ${e.message}")
        }
    }
}
