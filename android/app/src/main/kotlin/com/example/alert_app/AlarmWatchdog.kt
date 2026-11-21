package com.example.alert_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock

object AlarmWatchdog {
    const val ACTION_WATCHDOG_HEARTBEAT = "com.example.alert_app.WATCHDOG_HEARTBEAT"
    private const val REQUEST_CODE = 8888

    /**
     * Schedules the next hardware RTC watchdog wakeup.
     * Uses AlarmManager.setAlarmClock() which is exempt from Doze mode,
     * App Standby buckets, and deep CPU sleep.
     */
    fun scheduleNextWatchdog(context: Context, delayMillis: Long = 15000L) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val intent = Intent(context, BootAndAlarmReceiver::class.java).apply {
            action = ACTION_WATCHDOG_HEARTBEAT
        }

        val pendingIntent = PendingIntent.getBroadcast(
            context.applicationContext,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val triggerTime = System.currentTimeMillis() + delayMillis

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                // AlarmClockInfo has the highest priority on Android.
                // It physically wakes the device CPU from deep sleep and Doze mode.
                val showIntent = PendingIntent.getActivity(
                    context.applicationContext,
                    0,
                    Intent(context.applicationContext, MainActivity::class.java),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                val clockInfo = AlarmManager.AlarmClockInfo(triggerTime, showIntent)
                alarmManager.setAlarmClock(clockInfo, pendingIntent)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerTime, pendingIntent)
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerTime, pendingIntent)
            }
        } catch (_: Exception) {
            // Fallback to inexact or standard elapsed realtime if exact alarm permission is restricted
            try {
                alarmManager.set(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    SystemClock.elapsedRealtime() + delayMillis,
                    pendingIntent
                )
            } catch (_: Exception) {}
        }
    }

    fun cancelWatchdog(context: Context) {
        try {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val intent = Intent(context, BootAndAlarmReceiver::class.java).apply {
                action = ACTION_WATCHDOG_HEARTBEAT
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context.applicationContext,
                REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.cancel(pendingIntent)
        } catch (_: Exception) {}
    }
}
