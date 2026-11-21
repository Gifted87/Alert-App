package com.example.alert_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.PowerManager
import androidx.core.content.ContextCompat

class BootAndAlarmReceiver : BroadcastReceiver() {
    companion object {
        private const val WAKELOCK_TAG = "AlertApp:BootAndAlarmWakeLock"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return

        // 1. Acquire a temporary wake lock so CPU stays awake during processing
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val wakeLock = powerManager?.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            WAKELOCK_TAG
        )?.apply {
            setReferenceCounted(false)
            acquire(15000L) // 15 seconds safe max timeout
        }

        try {
            when (action) {
                Intent.ACTION_BOOT_COMPLETED,
                "android.intent.action.QUICKBOOT_POWERON",
                "com.htc.intent.action.QUICKBOOT_POWERON",
                Intent.ACTION_MY_PACKAGE_REPLACED,
                Intent.ACTION_USER_PRESENT -> {
                    val preferences = context.getSharedPreferences(AlertForegroundService.PREFS_NAME, Context.MODE_PRIVATE)
                    AlertDeadlineScheduler.schedule(
                        context,
                        preferences.getString(AlertForegroundService.KEY_ACTIVE_ALERTS, "[]") ?: "[]"
                    )
                    if (preferences.getString("setting_perpetual_service", "true") != "true") {
                        AlarmWatchdog.cancelWatchdog(context)
                        return
                    }
                    // System boot or app update: Launch perpetual foreground service immediately
                    val serviceIntent = Intent(context, AlertForegroundService::class.java).apply {
                        this.action = AlertForegroundService.ACTION_START
                    }
                    ContextCompat.startForegroundService(context, serviceIntent)

                    // Kickstart the hardware watchdog
                    AlarmWatchdog.scheduleNextWatchdog(context, 10000L)
                }

                AlarmWatchdog.ACTION_WATCHDOG_HEARTBEAT -> {
                    val preferences = context.getSharedPreferences(AlertForegroundService.PREFS_NAME, Context.MODE_PRIVATE)
                    if (preferences.getString("setting_perpetual_service", "true") != "true") {
                        AlarmWatchdog.cancelWatchdog(context)
                        return
                    }
                    // Watchdog heartbeat: ensure service is alive and check prices
                    val serviceIntent = Intent(context, AlertForegroundService::class.java).apply {
                        // ACTION_TRIGGER_CHECK also promotes a newly recreated service to
                        // foreground, so it is safe whether the monitor is alive or was killed.
                        this.action = AlertForegroundService.ACTION_TRIGGER_CHECK
                    }
                    ContextCompat.startForegroundService(context, serviceIntent)

                    // Schedule next watchdog heartbeat in 15 seconds
                    AlarmWatchdog.scheduleNextWatchdog(context, 15000L)
                }
            }
        } catch (_: Exception) {
        } finally {
            try {
                if (wakeLock?.isHeld == true) {
                    wakeLock.release()
                }
            } catch (_: Exception) {}
        }
    }
}
