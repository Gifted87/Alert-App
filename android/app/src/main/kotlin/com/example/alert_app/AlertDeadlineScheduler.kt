package com.example.alert_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

/** Persists deadline delivery through AlarmManager so snooze/TTL work without Dart alive. */
object AlertDeadlineScheduler {
    const val ACTION_DEADLINE = "com.example.alert_app.ALERT_DEADLINE"
    const val EXTRA_ALERT_ID = "alert_id"
    const val EXTRA_KIND = "deadline_kind"
    const val KIND_SNOOZE = "snooze"
    const val KIND_TTL = "ttl"
    const val KIND_SCHEDULE = "schedule"

    fun schedule(context: Context, alertsJson: String) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val prefs = context.getSharedPreferences(AlertForegroundService.PREFS_NAME, Context.MODE_PRIVATE)
        val ttlMillis = ttlMillis(prefs)
        val now = System.currentTimeMillis()
        try {
            val alerts = JSONArray(alertsJson)
            for (index in 0 until alerts.length()) {
                val alert = alerts.optJSONObject(index) ?: continue
                if (!alert.optBoolean("isActive", true)) continue
                val id = alert.optString("id").takeIf { it.isNotBlank() } ?: continue
                if (alert.optString("alertType") == "timeSchedule") {
                    parseTime(alert.optString("scheduledTime"))?.let {
                        setAlarm(context, alarms, id, KIND_SCHEDULE, maxOf(now, it))
                    }
                }
                parseTime(alert.optString("snoozedUntil"))?.let {
                    setAlarm(context, alarms, id, KIND_SNOOZE, maxOf(now, it))
                }
                if (ttlMillis != null) {
                    parseTime(alert.optString("createdAt"))?.let { created ->
                        setAlarm(context, alarms, id, KIND_TTL, maxOf(now, created + ttlMillis))
                    }
                }
            }
        } catch (_: Exception) { }
    }

    private fun setAlarm(context: Context, alarms: AlarmManager, id: String, kind: String, at: Long) {
        val requestCode = 31 * id.hashCode() + kind.hashCode()
        val intent = Intent(context, AlertDeadlineReceiver::class.java).apply {
            action = ACTION_DEADLINE
            putExtra(EXTRA_ALERT_ID, id)
            putExtra(EXTRA_KIND, kind)
        }
        val pending = PendingIntent.getBroadcast(
            context, requestCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0
        )
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms.canScheduleExactAlarms()) {
                    alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
                } else {
                    alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
                }
            } else {
                alarms.setExact(AlarmManager.RTC_WAKEUP, at, pending)
            }
        } catch (_: SecurityException) {
            try { alarms.set(AlarmManager.RTC_WAKEUP, at, pending) } catch (_: Exception) { }
        }
    }

    private fun ttlMillis(prefs: android.content.SharedPreferences): Long? {
        val raw = prefs.all["setting_alert_ttl"] ?: prefs.all["flutter.setting_alert_ttl"]
        val value = raw as? String ?: return null
        return when {
            value.contains("24", true) || value.contains("hour", true) -> ChronoUnit.HOURS.duration.toMillis() * 24
            value.contains("3", true) && value.contains("day", true) -> ChronoUnit.DAYS.duration.toMillis() * 3
            value.contains("1", true) && value.contains("week", true) -> ChronoUnit.DAYS.duration.toMillis() * 7
            else -> null
        }
    }

    fun parseTime(value: String?): Long? {
        val text = value?.takeIf { it.isNotBlank() && it != "null" } ?: return null
        return try {
            Instant.parse(text).toEpochMilli()
        } catch (_: Exception) {
            try {
                OffsetDateTime.parse(text, DateTimeFormatter.ISO_DATE_TIME).toInstant().toEpochMilli()
            } catch (_: Exception) {
                try {
                    LocalDateTime.parse(text, DateTimeFormatter.ISO_LOCAL_DATE_TIME)
                        .atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
                } catch (_: Exception) { null }
            }
        }
    }
}

class AlertDeadlineReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != AlertDeadlineScheduler.ACTION_DEADLINE) return
        val id = intent.getStringExtra(AlertDeadlineScheduler.EXTRA_ALERT_ID) ?: return
        val kind = intent.getStringExtra(AlertDeadlineScheduler.EXTRA_KIND) ?: return
        val prefs = context.getSharedPreferences(AlertForegroundService.PREFS_NAME, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val active = try { JSONArray(prefs.getString(AlertForegroundService.KEY_ACTIVE_ALERTS, "[]")) }
            catch (_: Exception) { JSONArray() }
        val savedRaw = prefs.getString("saved_alerts", prefs.getString("flutter.saved_alerts", "[]"))
        val saved = try { JSONArray(savedRaw) } catch (_: Exception) { JSONArray() }
        if (kind == AlertDeadlineScheduler.KIND_SCHEDULE) {
            val alert = (0 until active.length()).mapNotNull { active.optJSONObject(it) }
                .firstOrNull { it.optString("id") == id }
                ?: (0 until saved.length()).mapNotNull { saved.optJSONObject(it) }
                    .firstOrNull { it.optString("id") == id }
            val scheduledTime = AlertDeadlineScheduler.parseTime(alert?.optString("scheduledTime"))
            if (alert != null && alert.optBoolean("isActive", true) &&
                alert.optString("alertType") == "timeSchedule" &&
                scheduledTime != null && scheduledTime <= now) {
                val service = Intent(context, AlertForegroundService::class.java).apply {
                    action = AlertForegroundService.ACTION_TRIGGER_CHECK
                }
                androidx.core.content.ContextCompat.startForegroundService(context, service)
            }
            return
        }
        var changed = false
        val activeOut = JSONArray()
        for (i in 0 until active.length()) {
            val alert = active.optJSONObject(i) ?: continue
            if (alert.optString("id") == id) {
                if (kind == AlertDeadlineScheduler.KIND_SNOOZE) {
                    val until = AlertDeadlineScheduler.parseTime(alert.optString("snoozedUntil")) ?: Long.MAX_VALUE
                    if (until <= now) { alert.remove("snoozedUntil"); changed = true }
                } else if (kind == AlertDeadlineScheduler.KIND_TTL && expired(alert, prefs, now)) {
                    changed = true
                    continue
                }
            }
            activeOut.put(alert)
        }
        val savedOut = JSONArray()
        for (i in 0 until saved.length()) {
            val alert = saved.optJSONObject(i) ?: continue
            if (alert.optString("id") == id) {
                if (kind == AlertDeadlineScheduler.KIND_SNOOZE) {
                    val until = AlertDeadlineScheduler.parseTime(alert.optString("snoozedUntil")) ?: Long.MAX_VALUE
                    if (until <= now) { alert.remove("snoozedUntil"); changed = true }
                } else if (kind == AlertDeadlineScheduler.KIND_TTL && expired(alert, prefs, now)) {
                    alert.put("isActive", false)
                    alert.remove("snoozedUntil")
                    changed = true
                }
            }
            savedOut.put(alert)
        }
        if (changed) {
            val activeJson = activeOut.toString()
            val savedJson = savedOut.toString()
            prefs.edit().putString(AlertForegroundService.KEY_ACTIVE_ALERTS, activeJson)
                .putString("saved_alerts", savedJson).apply {
                    if (prefs.contains("flutter.saved_alerts")) putString("flutter.saved_alerts", savedJson)
                }.apply()
            AlertDeadlineScheduler.schedule(context, activeJson)
            val monitoring = prefs.getString("setting_perpetual_service", prefs.getString("flutter.setting_perpetual_service", "true")) == "true"
            if (monitoring) {
                val service = Intent(context, AlertForegroundService::class.java).apply { action = AlertForegroundService.ACTION_SYNC_ALERTS }
                androidx.core.content.ContextCompat.startForegroundService(context, service)
            }
        }
    }

    private fun expired(alert: JSONObject, prefs: android.content.SharedPreferences, now: Long): Boolean {
        val raw = prefs.all["setting_alert_ttl"] ?: prefs.all["flutter.setting_alert_ttl"]
        val ttl = when ((raw as? String)?.lowercase()) {
            "24 hours" -> 24L * 60 * 60 * 1000
            "3 days" -> 3L * 24 * 60 * 60 * 1000
            "1 week" -> 7L * 24 * 60 * 60 * 1000
            else -> return false
        }
        val created = AlertDeadlineScheduler.parseTime(alert.optString("createdAt")) ?: return false
        return now >= created + ttl
    }
}
