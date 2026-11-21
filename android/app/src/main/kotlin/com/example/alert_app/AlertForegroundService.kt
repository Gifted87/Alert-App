package com.example.alert_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.media.AudioManager
import android.media.ToneGenerator
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.graphics.PixelFormat
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

class AlertForegroundService : Service() {
    private val biquoteHostnameVerifier = javax.net.ssl.HostnameVerifier { _, session ->
        javax.net.ssl.HttpsURLConnection.getDefaultHostnameVerifier().verify("biquote.io", session)
    }

    companion object {
        const val CHANNEL_ID = "forex_alert_tracker_perpetual"
        const val ALARM_CHANNEL_ID = "forex_alert_alarm_high_priority"
        const val NOTIFICATION_ID = 1001
        const val ALARM_NOTIFICATION_BASE_ID = 2000
        const val LOW_BATTERY_NOTIFICATION_ID = 1999
        const val LOW_BATTERY_CHANNEL_ID = "tenx_low_battery_warning"
        const val ACTION_START = "ACTION_START"
        const val ACTION_STOP = "ACTION_STOP"
        const val ACTION_DISMISS_ALARM = "ACTION_DISMISS_ALARM"
        const val ACTION_SYNC_ALERTS = "ACTION_SYNC_ALERTS"
        const val ACTION_TRIGGER_CHECK = "ACTION_TRIGGER_CHECK"
        const val EXTRA_ALERTS_JSON = "alerts_json"
        const val PREFS_NAME = "FlutterSharedPreferences"
        const val KEY_ACTIVE_ALERTS = "flutter.active_alerts_sync"
        const val KEY_MONITOR_RUNNING = "native_monitor_running"
        const val KEY_MONITOR_LAST_CHECK = "native_monitor_last_check_ms"
        const val KEY_CURRENT_ALARM_ALERT_ID = "native_current_alarm_alert_id"
        const val KEY_DISMISSED_ALARM_ALERT_ID = "native_dismissed_alarm_alert_id"

        @Volatile
        var isServiceRunning: Boolean = false
            private set

        @Volatile
        var isExplicitStop: Boolean = false
            private set
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var scheduler: ScheduledExecutorService? = null
    private val checkExecutor = Executors.newSingleThreadExecutor()
    private val alarmHandler = Handler(Looper.getMainLooper())
    private var autoSilenceRunnable: Runnable? = null
    private var lastLowBatteryQuoteCheckAt = 0L

    @Volatile private var isNetworkConnected: Boolean = true
    @Volatile private var lastPriceCheckSuccessMs: Long = System.currentTimeMillis()
    @Volatile private var lastScheduledTickMs: Long = System.currentTimeMillis()
    @Volatile private var lastNotificationText: String = "Monitoring active forex price alerts in real time"
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    override fun onCreate() {
        super.onCreate()
        isServiceRunning = true
        isExplicitStop = false
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_MONITOR_RUNNING, true)
            .apply()
        createNotificationChannels()
        acquireWakeLock()
        registerNetworkCallback()
        startBackgroundMonitor()
        AlarmWatchdog.scheduleNextWatchdog(this, 15000L)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        isServiceRunning = true

        when (intent?.action) {
            ACTION_STOP -> {
                isExplicitStop = true
                AlarmWatchdog.cancelWatchdog(this)
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_DISMISS_ALARM -> {
                autoSilenceRunnable?.let { alarmHandler.removeCallbacks(it) }
                autoSilenceRunnable = null
                val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val currentAlertId = prefs.getString(KEY_CURRENT_ALARM_ALERT_ID, null)
                if (!currentAlertId.isNullOrBlank()) {
                    prefs.edit().putString(KEY_DISMISSED_ALARM_ALERT_ID, currentAlertId).commit()
                }
                AlarmHudOverlay.dismiss()
                AlarmPlayer.stopAlarm(this)
                val manager = getSystemService(NotificationManager::class.java)
                for (idOffset in 0 until 1000) {
                    manager.cancel(ALARM_NOTIFICATION_BASE_ID + idOffset)
                }
                val notification = buildNotification("Monitoring active forex price alerts in real time")
                manager.notify(NOTIFICATION_ID, notification)
            }
            ACTION_SYNC_ALERTS -> {
                // The Flutter UI sends a complete durable snapshot with every
                // sync. Persist it before evaluating so a task removal cannot
                // race an asynchronous preference write.
                intent.getStringExtra(EXTRA_ALERTS_JSON)?.let { alertsJson ->
                    val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    prefs
                        .edit()
                        .putString(KEY_ACTIVE_ALERTS, alertsJson)
                        .commit()
                    val dismissedId = prefs.getString(KEY_DISMISSED_ALARM_ALERT_ID, null)
                    if (!dismissedId.isNullOrBlank()) {
                        val matchingAlert = try {
                            val list = JSONArray(alertsJson)
                            (0 until list.length()).mapNotNull { list.optJSONObject(it) }
                                .firstOrNull { it.optString("id") == dismissedId }
                        } catch (_: Exception) { null }
                        // Clear dismissal only when the user re-arms/resets that
                        // alert, or removes it. Routine state sync keeps it muted.
                        if (matchingAlert == null || !matchingAlert.optBoolean("isActive", true)
                            || matchingAlert.isNull("triggeredAt")) {
                            prefs.edit().remove(KEY_DISMISSED_ALARM_ALERT_ID).apply()
                        }
                    }
                }
                startForeground(
                    NOTIFICATION_ID,
                    buildNotification(lastNotificationText)
                )
                ensureMonitorActive()
                checkExecutor.execute { triggerPriceCheck() }
                AlarmWatchdog.scheduleNextWatchdog(this, 15000L)
            }
            ACTION_TRIGGER_CHECK -> {
                startForeground(
                    NOTIFICATION_ID,
                    buildNotification(lastNotificationText)
                )
                ensureMonitorActive()
                checkExecutor.execute { triggerPriceCheck() }
                AlarmWatchdog.scheduleNextWatchdog(this, 15000L)
            }
            else -> {
                val notification = buildNotification(lastNotificationText)
                startForeground(NOTIFICATION_ID, notification)
                startBackgroundMonitor()
                checkExecutor.execute { triggerPriceCheck() }
                AlarmWatchdog.scheduleNextWatchdog(this, 15000L)
            }
        }

        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        // The service is independent of the UI task. Keep a hardware watchdog armed in case
        // Android or an OEM process manager terminates the service process after task removal.
        if (!isExplicitStop) {
            ensureMonitorActive()
            AlarmWatchdog.scheduleNextWatchdog(applicationContext, 5000L)
        }
    }

    private fun ensureMonitorActive() {
        val now = System.currentTimeMillis()
        val isStalled = scheduler == null || scheduler?.isShutdown == true || (now - lastScheduledTickMs > 30000L)
        if (isStalled) {
            startBackgroundMonitor()
        }
    }

    private fun registerNetworkCallback() {
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
            val activeNetwork = cm.activeNetwork
            val capabilities = cm.getNetworkCapabilities(activeNetwork)
            isNetworkConnected = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true

            val request = NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build()

            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    val wasDisconnected = !isNetworkConnected
                    isNetworkConnected = true
                    val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    updateConnectionStatus(prefs, connected = true)
                    ensureMonitorActive()
                    checkExecutor.execute {
                        try {
                            triggerPriceCheck()
                        } catch (_: Throwable) {}
                    }
                }

                override fun onLost(network: Network) {
                    isNetworkConnected = false
                    val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    updateConnectionStatus(prefs, connected = false, reason = "Internet connection lost")
                }
            }
            networkCallback = callback
            cm.registerNetworkCallback(request, callback)
        } catch (_: Throwable) {}
    }

    private fun unregisterNetworkCallback() {
        try {
            networkCallback?.let {
                val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                cm?.unregisterNetworkCallback(it)
            }
        } catch (_: Throwable) {}
        networkCallback = null
    }

    private fun startBackgroundMonitor() {
        try {
            scheduler?.shutdownNow()
        } catch (_: Throwable) {}
        scheduler = null

        scheduler = Executors.newSingleThreadScheduledExecutor()
        val preferences = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val pollingRate = preferences.getString("setting_polling_rate", "Standard (5s)") ?: "Standard (5s)"
        val intervalSeconds = when {
            pollingRate.contains("2s") -> 2L
            pollingRate.contains("15s") -> 15L
            else -> 5L
        }
        scheduler?.scheduleWithFixedDelay({
            try {
                lastScheduledTickMs = System.currentTimeMillis()
                triggerPriceCheck()
            } catch (_: Throwable) {
                // Must catch Throwable so ScheduledExecutorService thread never terminates
            }
        }, 0, intervalSeconds, TimeUnit.SECONDS)
    }

    private fun playConfiguredAlarm(ringtoneUri: String?, ttsText: String, isCritical: Boolean = false) {
        val preferences = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        fun stringSetting(key: String, default: String) =
            preferences.getString(key, default) ?: default
        fun boolSetting(key: String, default: Boolean) =
            stringSetting(key, default.toString()).toBoolean()

        val forceMaxVolume = boolSetting("setting_force_max_vol", false)
        val alarmVolume = stringSetting("setting_alarm_volume", "0.85")
            .toDoubleOrNull()?.coerceIn(0.0, 1.0) ?: 0.85
        val quietVolume = stringSetting("setting_quiet_hours_vol", "0.25")
            .toDoubleOrNull()?.coerceIn(0.0, 1.0) ?: 0.25
        val inQuietHours = boolSetting("setting_quiet_hours_enabled", true) && run {
            val times = Regex("(\\d{1,2}:\\d{2})[^\\d]+(\\d{1,2}:\\d{2})")
                .find(stringSetting("setting_quiet_hours", "23:00 – 07:00"))
            val start = times?.groupValues?.getOrNull(1)
            val end = times?.groupValues?.getOrNull(2)
            if (start == null || end == null) false else try {
                val now = java.util.Calendar.getInstance()
                val currentMinutes = now.get(java.util.Calendar.HOUR_OF_DAY) * 60 + now.get(java.util.Calendar.MINUTE)
                fun minutes(value: String): Int {
                    val parts = value.split(":")
                    return parts[0].toInt() * 60 + parts[1].toInt()
                }
                val startMinutes = minutes(start)
                val endMinutes = minutes(end)
                if (startMinutes <= endMinutes) currentMinutes >= startMinutes && currentMinutes < endMinutes
                else currentMinutes >= startMinutes || currentMinutes < endMinutes
            } catch (_: Exception) { false }
        }
        val bypassQuietHours = isCritical && boolSetting("setting_quiet_bypass", true)
        val volume = if (inQuietHours && !bypassQuietHours) quietVolume else alarmVolume
        val configuredUri = ringtoneUri?.takeIf { it.isNotBlank() }
            ?: stringSetting("setting_global_sound_uri", "default_alarm")
        val ttsRate = stringSetting("setting_tts_rate", "1.0x")

        autoSilenceRunnable?.let { alarmHandler.removeCallbacks(it) }
        autoSilenceRunnable = null
        AlarmPlayer.playAlarm(
            this,
            configuredUri,
            looping = true,
            volume = volume,
            forceMaxVolume = forceMaxVolume,
            volumeEscalation = boolSetting("setting_volume_escalation", true),
            vibrationMode = stringSetting("setting_vibration_mode", "Continuous"),
            audioDucking = boolSetting("setting_audio_ducking", true),
            flashlightStrobe = boolSetting("setting_flashlight_strobe", false),
            headphoneSafety = boolSetting("setting_headphone_safety", true),
            screenWakeup = boolSetting("setting_screen_wakeup", true),
            ttsText = if (boolSetting("setting_tts_enabled", false)) ttsText else null,
            ttsRate = ttsRate
        )

        val silenceSeconds = when {
            stringSetting("setting_auto_silence", "Never").contains("30") -> 30L
            stringSetting("setting_auto_silence", "Never").contains("60") -> 60L
            else -> 0L
        }
        if (silenceSeconds > 0) {
            val runnable = Runnable { AlarmPlayer.stopAlarm(this) }
            autoSilenceRunnable = runnable
            alarmHandler.postDelayed(runnable, silenceSeconds * 1000)
        }
    }

    private fun triggerPriceCheck() {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putLong(KEY_MONITOR_LAST_CHECK, System.currentTimeMillis())
            .apply()
        // Acquire temporary wake lock during price network fetch
        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
        val tempWakeLock = powerManager?.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "AlertApp:PriceCheckWakeLock"
        )?.apply {
            setReferenceCounted(false)
            acquire(10000L) // 10s safe timeout
        }

        try {
            val prefs: SharedPreferences = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val lowBatteryGuard = when (
                val raw = prefs.all["setting_low_battery_guard"]
                    ?: prefs.all["flutter.setting_low_battery_guard"]
            ) {
                is Boolean -> raw
                is String -> raw.toBoolean()
                else -> true
            }
            val batteryManager = getSystemService(Context.BATTERY_SERVICE) as? android.os.BatteryManager
            val batteryLevel = batteryManager?.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
            val isBatteryThrottled = lowBatteryGuard && batteryLevel in 0..15
            if (isBatteryThrottled) {
                postLowBatteryWarning(batteryLevel)
            } else if (!lowBatteryGuard || batteryLevel > 20) {
                getSystemService(NotificationManager::class.java).cancel(LOW_BATTERY_NOTIFICATION_ID)
            }
            evaluateSessionOpenAlerts(prefs)
            // Keep session and battery checks frequent, but throttle market
            // quote traffic to at most once every 15 seconds below 16% battery.
            if (isBatteryThrottled) {
                val now = System.currentTimeMillis()
                if (now - lastLowBatteryQuoteCheckAt < TimeUnit.SECONDS.toMillis(15)) return
                lastLowBatteryQuoteCheckAt = now
            } else {
                lastLowBatteryQuoteCheckAt = 0L
            }
            var alertsJsonStr = prefs.getString(KEY_ACTIVE_ALERTS, null)
            if (alertsJsonStr.isNullOrBlank() || alertsJsonStr == "[]") {
                // The saved alert list is the durable source of truth. Recover it
                // if an app shutdown interrupted the separate active-list sync.
                val savedAlertsJson = prefs.getString("saved_alerts", null)
                    ?: prefs.getString("flutter.saved_alerts", null)
                if (!savedAlertsJson.isNullOrBlank()) {
                    try {
                        val savedAlerts = JSONArray(savedAlertsJson)
                        val recoveredAlerts = JSONArray()
                        for (index in 0 until savedAlerts.length()) {
                            val alert = savedAlerts.optJSONObject(index) ?: continue
                            if (alert.optBoolean("isActive", true)) {
                                recoveredAlerts.put(alert)
                            }
                        }
                        if (recoveredAlerts.length() > 0) {
                            alertsJsonStr = recoveredAlerts.toString()
                            prefs.edit()
                                .putString(KEY_ACTIVE_ALERTS, alertsJsonStr)
                                .apply()
                        }
                    } catch (_: Exception) {}
                }
            }
            if (alertsJsonStr.isNullOrEmpty() || alertsJsonStr == "[]") {
                updateConnectionLossWarning(prefs, connected = true)
                return
            }

            val alertsArray = JSONArray(alertsJsonStr)
            if (alertsArray.length() == 0) {
                updateConnectionLossWarning(prefs, connected = true)
                return
            }

            // ── Pre-pass: evaluate timeSchedule (calendar) alerts ──────────
            // These are wall-clock-based and don't need market data.
            val nowMs = System.currentTimeMillis()
            val scheduleRemaining = JSONArray()
            var scheduleTriggered: JSONObject? = null
            for (i in 0 until alertsArray.length()) {
                val a = alertsArray.getJSONObject(i)
                if (isSnoozed(a, nowMs)) {
                    scheduleRemaining.put(a)
                    continue
                }
                val at = a.optString("alertType", "priceLevel")
                if (at == "timeSchedule") {
                    val scheduledMs = AlertDeadlineScheduler.parseTime(a.optString("scheduledTime"))
                    if (scheduledMs != null && nowMs >= scheduledMs && scheduleTriggered == null) {
                        scheduleTriggered = a
                        continue // Don't add to remaining
                    }
                    scheduleRemaining.put(a) // Not yet due, keep it
                } else {
                    scheduleRemaining.put(a) // Non-schedule alert, carry forward
                }
            }

            // If a calendar alert fired, persist changes and alarm immediately
            if (scheduleTriggered != null) {
                prefs.edit().putString(KEY_ACTIVE_ALERTS, scheduleRemaining.toString()).apply()
                syncToFlutterStorage(prefs, scheduleTriggered, scheduleRemaining)

                val symbol = scheduleTriggered.optString("symbol")
                val eventName = scheduleTriggered.optString("eventName", "Calendar Event")
                val ringtoneUri = scheduleTriggered.optString("ringtoneUri").takeIf { it.isNotEmpty() }
                val isCritical = scheduleTriggered.optString("impact").contains("high", ignoreCase = true) ||
                    eventName.contains("high impact", ignoreCase = true)
                playConfiguredAlarm(
                    ringtoneUri,
                    "Calendar alert: $eventName for $symbol.",
                    isCritical
                )
                postAlarmNotification(
                    "📅 CALENDAR ALERT: $symbol",
                    "$eventName is about to be released!",
                    symbol = symbol
                )
                // Continue to also evaluate market-based alerts below
            }

            // Use the filtered array (without triggered schedule alerts) for remaining checks
            val activeAlertsArray = if (scheduleTriggered != null) scheduleRemaining else alertsArray

            // Collect unique symbols to query (skip timeSchedule alerts, they don't need quotes)
            val symbols = mutableSetOf<String>()
            for (i in 0 until activeAlertsArray.length()) {
                val alert = activeAlertsArray.getJSONObject(i)
                if (isSnoozed(alert, nowMs)) continue
                val at = alert.optString("alertType", "priceLevel")
                if (at == "timeSchedule") continue
                val symbol = alert.optString("symbol")
                if (symbol.isNotEmpty()) {
                    symbols.add(symbol)
                }
            }
            if (symbols.isEmpty()) {
                updateConnectionLossWarning(prefs, connected = true)
                return
            }

            // Build query params
            val queryParams = symbols.joinToString("&") { "symbols=$it" }
            var responseStr: String? = null

            // Primary API: biquote.io
            try {
                val url = URL("https://biquote.io/api/latest?$queryParams&allowStale=true")
                val connection = url.openConnection() as HttpURLConnection
                connection.requestMethod = "GET"
                connection.connectTimeout = 4000
                connection.readTimeout = 4000
                if (connection.responseCode == 200) {
                    val reader = BufferedReader(InputStreamReader(connection.inputStream))
                    responseStr = reader.readText()
                    reader.close()
                }
                connection.disconnect()
            } catch (_: Exception) {}

            // Fallback direct IP if DNS failed during deep sleep
            val allowDirectIpFallback = when (
                val raw = prefs.all["setting_direct_ip_fallback"]
                    ?: prefs.all["flutter.setting_direct_ip_fallback"]
            ) {
                is Boolean -> raw
                is String -> raw.toBoolean()
                else -> true
            }
            if (responseStr == null && allowDirectIpFallback) {
                try {
                    val url = URL("https://142.132.248.240/api/latest?$queryParams&allowStale=true")
                    val connection = url.openConnection() as javax.net.ssl.HttpsURLConnection
                    connection.hostnameVerifier = biquoteHostnameVerifier
                    connection.setRequestProperty("Host", "biquote.io")
                    connection.requestMethod = "GET"
                    connection.connectTimeout = 4000
                    connection.readTimeout = 4000
                    if (connection.responseCode == 200) {
                        val reader = BufferedReader(InputStreamReader(connection.inputStream))
                        responseStr = reader.readText()
                        reader.close()
                    }
                    connection.disconnect()
                } catch (_: Exception) {}
            }

            updateConnectionLossWarning(prefs, responseStr != null)

            if (responseStr != null) {
                val quotesJson = JSONObject(responseStr)
                var triggeredAlert: JSONObject? = null
                var triggeredPrice = 0.0
                var alertsModified = false
                val remainingAlerts = JSONArray()

                // Pre-cache OHLC bars for all needed (symbol, timeframe) pairs once per check
                for (i in 0 until activeAlertsArray.length()) {
                    val a = activeAlertsArray.getJSONObject(i)
                    if (isSnoozed(a, nowMs)) continue
                    if (isInCooldown(a)) continue
                    val sym = a.optString("symbol")
                    val at = a.optString("alertType", "priceLevel")
                    val tf = a.optString("timeframe", "15m")
                    if (at == "candlestickPattern" || at == "technicalIndicator") {
                        fetchOhlcBars(sym, tf, 250)
                    } else if (at == "multiStepChain") {
                        val msc = a.optJSONObject("multiStepConfig")
                        val stgs = msc?.optJSONArray("stages")
                        val curIdx = msc?.optInt("currentStageIndex", 0) ?: 0
                        if (stgs != null && curIdx < stgs.length()) {
                            val stg = stgs.getJSONObject(curIdx)
                            val nds = stg.optJSONArray("nodes")
                            if (nds != null) {
                                for (n in 0 until nds.length()) {
                                    val node = nds.getJSONObject(n)
                                    val nt = node.optString("nodeType")
                                    val ntf = node.optString("timeframe", "15m")
                                    if (nt == "candlestickPattern" || nt == "technicalIndicator") {
                                        fetchOhlcBars(sym, ntf, 250)
                                    }
                                }
                            }
                        }
                    }
                }

                for (i in 0 until activeAlertsArray.length()) {
                    val alert = activeAlertsArray.getJSONObject(i)
                    val dismissedId = prefs.getString(KEY_DISMISSED_ALARM_ALERT_ID, null)
                    if (!dismissedId.isNullOrBlank() && alert.optString("id") == dismissedId) {
                        remainingAlerts.put(alert)
                        continue
                    }
                    if (isSnoozed(alert, nowMs)) {
                        remainingAlerts.put(alert)
                        continue
                    }
                    val alertType = alert.optString("alertType", "priceLevel")
                    val symbol = alert.optString("symbol")

                    // Cooldown Hysteresis Filter: Skip evaluation if alert is within deadband
                    if (isInCooldown(alert)) {
                        val tickObj = quotesJson.optJSONObject(symbol)
                        val currentPrice = tickObj?.optDouble("mid", 0.0) ?: 0.0
                        if (currentPrice > 0.0) {
                            alert.put("previousPrice", currentPrice)
                            alertsModified = true
                        }
                        remainingAlerts.put(alert)
                        continue
                    }
                    // timeSchedule alerts are handled in the pre-pass above
                    if (alertType == "timeSchedule") {
                        remainingAlerts.put(alert)
                        continue
                    }

                    if (alertType == "candlestickPattern") {
                        val pattern = alert.optString("candlestickPattern", "")
                        val timeframe = alert.optString("timeframe", "15m")
                        val detectedPrice = if (triggeredAlert == null && pattern.isNotEmpty()) {
                            checkCandlestickPattern(symbol, timeframe, pattern)
                        } else null

                        if (detectedPrice != null && triggeredAlert == null) {
                            triggeredAlert = alert
                            triggeredPrice = detectedPrice
                        } else {
                            remainingAlerts.put(alert)
                        }
                    } else if (alertType == "technicalIndicator") {
                        val timeframe = alert.optString("timeframe", "15m")
                        val indicatorConfig = alert.optJSONObject("indicatorConfig")
                        val detectedPrice = if (triggeredAlert == null && indicatorConfig != null) {
                            checkTechnicalIndicator(symbol, timeframe, indicatorConfig)
                        } else null

                        if (detectedPrice != null && triggeredAlert == null) {
                            triggeredAlert = alert
                            triggeredPrice = detectedPrice
                        } else {
                            remainingAlerts.put(alert)
                        }
                    } else if (alertType == "multiStepChain") {
                        val multiStepConfig = alert.optJSONObject("multiStepConfig")
                        if (multiStepConfig != null) {
                            var currentStageIndex = multiStepConfig.optInt("currentStageIndex", 0)
                            val stages = multiStepConfig.optJSONArray("stages")
                            val globalTimeoutMinutes = multiStepConfig.optInt("timeoutMinutes", 30)

                            // Step Timeout Expiry Enforcement:
                            // If a previous step was completed, verify that the timeout has not expired.
                            if (stages != null && currentStageIndex > 0 && currentStageIndex < stages.length()) {
                                val prevStage = stages.getJSONObject(currentStageIndex - 1)
                                val completedAtStr = prevStage.optString("completedAt", "")
                                val stageLimit = if (prevStage.has("timeoutMinutes")) prevStage.optInt("timeoutMinutes") else globalTimeoutMinutes
                                val limitMinutes = if (stageLimit >= 0) stageLimit else globalTimeoutMinutes

                                if (completedAtStr.isNotEmpty() && limitMinutes > 0) {
                                    try {
                                        val completedTime = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                            java.time.Instant.parse(completedAtStr).toEpochMilli()
                                        } else {
                                            java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", java.util.Locale.US).parse(completedAtStr)?.time ?: 0L
                                        }
                                        val elapsedMs = System.currentTimeMillis() - completedTime
                                        if (elapsedMs >= limitMinutes * 60 * 1000L) {
                                            // Timeout reached! Reset chain back to Step 1
                                            currentStageIndex = 0
                                            multiStepConfig.put("currentStageIndex", 0)
                                            for (sIdx in 0 until stages.length()) {
                                                val stg = stages.getJSONObject(sIdx)
                                                stg.put("isCompleted", false)
                                                stg.remove("completedAt")
                                                val nds = stg.optJSONArray("nodes")
                                                if (nds != null) {
                                                    for (nIdx in 0 until nds.length()) {
                                                        val nd = nds.getJSONObject(nIdx)
                                                        nd.put("isSatisfied", false)
                                                        nd.remove("previousPrice")
                                                    }
                                                }
                                            }
                                            alertsModified = true
                                        }
                                    } catch (_: Exception) {}
                                }
                            }

                            if (stages != null && currentStageIndex < stages.length()) {
                                val stage = stages.getJSONObject(currentStageIndex)
                                val nodes = stage.optJSONArray("nodes") ?: JSONArray()
                                val logicOperator = stage.optString("logicOperator", "AND")

                                for (j in 0 until nodes.length()) {
                                    val node = nodes.getJSONObject(j)
                                    if (node.optBoolean("isSatisfied", false)) continue

                                    val nodeType = node.optString("nodeType", "priceLevel")
                                    val isNegated = node.optBoolean("isNegated", false)
                                    var rawSatisfied = false

                                    when (nodeType) {
                                        "priceLevel" -> {
                                            val tPrice = node.optDouble("targetPrice", 0.0)
                                            val cond = node.optString("condition")
                                            val tickObj = quotesJson.optJSONObject(symbol)
                                            val cPrice = tickObj?.optDouble("mid", 0.0) ?: 0.0
                                            val prevP = if (node.has("previousPrice")) node.optDouble("previousPrice") else alert.optDouble("initialPrice", 0.0)
                                            if (cPrice > 0.0 && tPrice > 0.0) {
                                                rawSatisfied = when (cond) {
                                                    "crossesAbove" -> (prevP > 0.0 && prevP < tPrice && cPrice >= tPrice)
                                                    "crossesBelow" -> (prevP > 0.0 && prevP > tPrice && cPrice <= tPrice)
                                                    "hits" -> Math.abs(cPrice - tPrice) <= (tPrice * 0.0002)
                                                    else -> false
                                                }
                                                node.put("previousPrice", cPrice)
                                                alertsModified = true
                                            }
                                        }
                                        "candlestickPattern" -> {
                                            val pat = node.optString("candlestickPattern", "")
                                            val tf = node.optString("timeframe", "15m")
                                            if (pat.isNotEmpty()) {
                                                val pPrice = checkCandlestickPattern(symbol, tf, pat)
                                                rawSatisfied = (pPrice != null)
                                            }
                                        }
                                        "technicalIndicator" -> {
                                            val tf = node.optString("timeframe", "15m")
                                            val iConfig = node.optJSONObject("indicatorConfig")
                                            if (iConfig != null) {
                                                val iPrice = checkTechnicalIndicator(symbol, tf, iConfig)
                                                rawSatisfied = (iPrice != null)
                                            }
                                        }
                                    }

                                    val finalSatisfied = if (isNegated) !rawSatisfied else rawSatisfied
                                    if (finalSatisfied) {
                                        node.put("isSatisfied", true)
                                        alertsModified = true
                                    }
                                }

                                var isStageCompleted = false
                                if (nodes.length() > 0) {
                                    isStageCompleted = nodes.getJSONObject(0).optBoolean("isSatisfied", false)
                                    for (j in 1 until nodes.length()) {
                                        val n = nodes.getJSONObject(j)
                                        val op = n.optString("operatorToPrevious", "AND")
                                        val sat = n.optBoolean("isSatisfied", false)
                                        isStageCompleted = if (op.equals("OR", ignoreCase = true)) {
                                            isStageCompleted || sat
                                        } else {
                                            isStageCompleted && sat
                                        }
                                    }
                                }

                                if (isStageCompleted) {
                                    stage.put("isCompleted", true)
                                    val nowIso = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                        java.time.Instant.now().toString()
                                    } else {
                                        java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US).format(java.util.Date())
                                    }
                                    stage.put("completedAt", nowIso)
                                    currentStageIndex++
                                    multiStepConfig.put("currentStageIndex", currentStageIndex)
                                    alertsModified = true

                                    if (currentStageIndex >= stages.length()) {
                                        // Terminal trigger!
                                        val tickObj = quotesJson.optJSONObject(symbol)
                                        val cPrice = tickObj?.optDouble("mid", 0.0) ?: 0.0
                                        triggeredAlert = alert
                                        triggeredPrice = cPrice
                                    }
                                }

                                if (triggeredAlert != alert) {
                                    remainingAlerts.put(alert)
                                }
                            } else {
                                remainingAlerts.put(alert)
                            }
                        } else {
                            remainingAlerts.put(alert)
                        }
                    } else {
                        // Standard price-level alert: Enforce stateful boundary crossing
                        val targetPrice = alert.optDouble("targetPrice", 0.0)
                        val condition = alert.optString("condition")
                        val tickObj = quotesJson.optJSONObject(symbol)
                        val currentPrice = tickObj?.optDouble("mid", 0.0) ?: 0.0
                        val previousPrice = if (alert.has("previousPrice")) alert.optDouble("previousPrice") else alert.optDouble("initialPrice", 0.0)

                        if (currentPrice > 0.0 && targetPrice > 0.0) {
                            val isTriggered = when (condition) {
                                "crossesAbove" -> (previousPrice > 0.0 && previousPrice < targetPrice && currentPrice >= targetPrice)
                                "crossesBelow" -> (previousPrice > 0.0 && previousPrice > targetPrice && currentPrice <= targetPrice)
                                "hits" -> Math.abs(currentPrice - targetPrice) <= (targetPrice * 0.0002)
                                else -> false
                            }
                            alert.put("previousPrice", currentPrice)
                            alertsModified = true

                            if (isTriggered && triggeredAlert == null) {
                                triggeredAlert = alert
                                triggeredPrice = currentPrice
                            } else {
                                remainingAlerts.put(alert)
                            }
                        } else {
                            remainingAlerts.put(alert)
                        }
                    }
                }

                // If any alert was modified or triggered
                if (triggeredAlert != null || alertsModified) {
                    val cooldownMin = triggeredAlert?.optInt("cooldownMinutes", 0) ?: 0
                    if (triggeredAlert != null && cooldownMin > 0) {
                        val nowIso = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            java.time.Instant.now().toString()
                        } else {
                            java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US).format(java.util.Date())
                        }
                        triggeredAlert.put("lastTriggeredAt", nowIso)
                        remainingAlerts.put(triggeredAlert)
                    }
                    prefs.edit().putString(KEY_ACTIVE_ALERTS, remainingAlerts.toString()).apply()
                    syncToFlutterStorage(prefs, triggeredAlert, remainingAlerts)
                }

                // If an alert was triggered
                if (triggeredAlert != null) {
                    val triggeredId = triggeredAlert.optString("id")
                    prefs.edit().putString(KEY_CURRENT_ALARM_ALERT_ID, triggeredId).commit()
                    if (prefs.getString(KEY_DISMISSED_ALARM_ALERT_ID, null) == triggeredId) {
                        // A dismissal may arrive while this market check is in flight.
                        // Keep the alert monitor alive, but never restart its sound/HUD.
                        return
                    }
                    val symbol = triggeredAlert.optString("symbol")
                    val alertType = triggeredAlert.optString("alertType", "priceLevel")
                    val ringtoneUri = triggeredAlert.optString("ringtoneUri").takeIf { it.isNotEmpty() }

                    // 1. Play loud alarm with screen wakeup and DND override
                    val ttsText = when (alertType) {
                        "candlestickPattern" -> "Candlestick pattern alert on $symbol."
                        "technicalIndicator" -> "Technical indicator alert on $symbol."
                        else -> "Price alert for $symbol triggered at $triggeredPrice."
                    }
                    val description = triggeredAlert.optString("eventName") + " " + triggeredAlert.optString("note")
                    val isCritical = description.contains("high impact", ignoreCase = true) ||
                        description.contains("stop loss", ignoreCase = true) ||
                        description.contains("stop-loss", ignoreCase = true)
                    playConfiguredAlarm(ringtoneUri, ttsText, isCritical)

                    // 2. Post high-priority alert notification with Dismiss button
                    if (alertType == "candlestickPattern") {
                        val pattern = triggeredAlert.optString("candlestickPattern")
                        val timeframe = triggeredAlert.optString("timeframe", "15m")
                        val formattedPattern = formatPatternName(pattern)
                        postAlarmNotification(
                            "🚨 PATTERN ALARM: $symbol",
                            "$formattedPattern confirmed on ${timeframe.uppercase()}! Triggered at: $triggeredPrice",
                            symbol = symbol,
                            triggerPrice = triggeredPrice
                        )
                    } else if (alertType == "technicalIndicator") {
                        val timeframe = triggeredAlert.optString("timeframe", "15m")
                        val indicatorConfig = triggeredAlert.optJSONObject("indicatorConfig")
                        val summary = formatIndicatorSummary(indicatorConfig)
                        postAlarmNotification(
                            "🚨 INDICATOR ALARM: $symbol",
                            "$summary on ${timeframe.uppercase()}! Triggered at: $triggeredPrice",
                            symbol = symbol,
                            triggerPrice = triggeredPrice
                        )
                    } else if (alertType == "multiStepChain") {
                        val note = triggeredAlert.optString("note", "Strategy Chain")
                        postAlarmNotification(
                            "🚨 STRATEGY CHAIN COMPLETED: $symbol",
                            "All levels passed! $note. Trigger price: $triggeredPrice",
                            symbol = symbol,
                            triggerPrice = triggeredPrice
                        )
                    } else {
                        val target = triggeredAlert.optDouble("targetPrice")
                        postAlarmNotification(
                            "🚨 PRICE ALERT TRIGGERED: $symbol",
                            "Target $target reached! Current price: $triggeredPrice",
                            symbol = symbol,
                            triggerPrice = triggeredPrice
                        )
                    }
                }

                // 3. Status Bar Ticker & Low Battery Guard
                val showTicker = try {
                    val all = prefs.all
                    val raw = all["setting_status_bar_ticker"] ?: all["flutter.setting_status_bar_ticker"]
                    when (raw) {
                        is Boolean -> raw
                        is String -> raw.toBoolean()
                        else -> true
                    }
                } catch (_: Exception) { true }

                val manager = getSystemService(NotificationManager::class.java)
                if (showTicker && quotesJson.length() > 0) {
                    var tickerSymbol = ""
                    for (i in 0 until activeAlertsArray.length()) {
                        val candidate = activeAlertsArray.getJSONObject(i).optString("symbol")
                        if (quotesJson.has(candidate)) {
                            tickerSymbol = candidate
                            break
                        }
                    }
                    if (tickerSymbol.isEmpty()) tickerSymbol = quotesJson.keys().next()
                    val tickObj = quotesJson.optJSONObject(tickerSymbol)
                    val mid = tickObj?.optDouble("mid", 0.0) ?: 0.0
                    val change24 = tickObj?.optDouble("dayDiffPercent", 0.0) ?: 0.0
                    val stale = tickObj?.optBoolean("stale", false) ?: false
                    val quoteAge = tickObj?.optInt("quoteAgeSeconds", 0) ?: 0
                    val sign = if (change24 >= 0) "▲ +" else "▼ "
                    val tickerPrefix = if (isBatteryThrottled) "⚡ [ECO 15%] " else ""
                    val precision = when {
                        tickerSymbol.contains("JPY") -> 3
                        tickerSymbol.contains("BTC") || tickerSymbol.contains("ETH") || tickerSymbol.contains("XAU") -> 2
                        else -> 5
                    }
                    val price = String.format(java.util.Locale.US, "%.${precision}f", mid)
                    val freshness = if (stale) " · STALE ${quoteAge}s" else ""
                    val tickerText = "$tickerPrefix$tickerSymbol: $price $sign${String.format(java.util.Locale.US, "%.2f", change24)}% · Alerts: ${activeAlertsArray.length()}$freshness"
                    val notification = buildNotification(tickerText)
                    manager.notify(NOTIFICATION_ID, notification)
                } else if (!showTicker) {
                    val notification = buildNotification("Monitoring ${activeAlertsArray.length()} active alerts in real time")
                    manager.notify(NOTIFICATION_ID, notification)
                }
            }
        } catch (_: Throwable) {
        } finally {
            try {
                if (tempWakeLock?.isHeld == true) {
                    tempWakeLock.release()
                }
            } catch (_: Exception) {}
        }
    }

    private fun evaluateSessionOpenAlerts(prefs: SharedPreferences) {
        val savedSessions = when (
            val raw = prefs.all["setting_trading_sessions"]
                ?: prefs.all["flutter.setting_trading_sessions"]
        ) {
            is String -> raw.split("|||").filter { it.isNotBlank() }
            else -> emptyList()
        }
        if (savedSessions.isEmpty()) return
        val timing = (prefs.all["setting_session_timing"]
            ?: prefs.all["flutter.setting_session_timing"]).toString()
        val offsetMinutes = when {
            timing.contains("15") -> 15
            timing.contains("5") -> 5
            else -> 0
        }
        val now = java.time.Instant.now().atZone(java.time.ZoneOffset.UTC)
        val currentMinutes = now.hour * 60 + now.minute
        val dateKey = now.toLocalDate().toString()
        val schedules = listOf(
            Triple("Sydney Open", 21, "AUD and NZD pairs active"),
            Triple("Tokyo Open", 0, "JPY pairs and Nikkei active"),
            Triple("London Open", 7, "GBP, EUR pairs and DAX active"),
            Triple("New York Open", 12, "USD pairs, Gold and indices active"),
            Triple("London / NY Overlap", 12, "Peak daily global liquidity window")
        )
        val fired = (prefs.getString("session_alerts_fired", "") ?: "")
            .split("|||").filter { it.isNotBlank() }.toMutableSet()
        var changed = false
        for ((name, hour, description) in schedules) {
            if (savedSessions.none { it.startsWith(name) }) continue
            val targetMinutes = (hour * 60 - offsetMinutes + 1440) % 1440
            val key = "$dateKey|$name"
            if (currentMinutes != targetMinutes || key in fired) continue
            fired.add(key)
            changed = true
            triggerSessionAlert(prefs, name, description)
        }
        if (changed) {
            val recent = fired.sorted().takeLast(45)
            prefs.edit().putString("session_alerts_fired", recent.joinToString("|||" )).apply()
        }
    }

    private fun triggerSessionAlert(prefs: SharedPreferences, name: String, description: String) {
        val nowIso = java.time.Instant.now().toString()
        val id = "session_${name.lowercase().replace(Regex("[^a-z0-9]+"), "_")}_${System.currentTimeMillis()}"
        val item = JSONObject().apply {
            put("id", id)
            put("symbol", "SESSION")
            put("alertType", "timeSchedule")
            put("targetPrice", 0.0)
            put("condition", "crossesAbove")
            put("timeframe", "15m")
            put("note", "$name ($description)")
            put("isActive", false)
            put("createdAt", nowIso)
            put("triggeredAt", nowIso)
            put("initialPrice", 0.0)
            put("ringtoneTitle", "Default Alarm")
            put("triggerOnCandleClose", true)
            put("cooldownMinutes", 0)
        }
        try {
            val historyStr = prefs.getString("saved_history", null)
                ?: prefs.getString("flutter.saved_history", null)
            val oldHistory = if (historyStr.isNullOrBlank()) JSONArray() else JSONArray(historyStr)
            val history = JSONArray().put(item)
            for (index in 0 until oldHistory.length()) history.put(oldHistory.getJSONObject(index))
            prefs.edit().putString("saved_history", history.toString())
                .putString("flutter.saved_history", history.toString()).apply()
        } catch (_: Exception) {}

        val soundUri = (prefs.all["setting_global_sound_uri"]
            ?: prefs.all["flutter.setting_global_sound_uri"])?.toString()
        playConfiguredAlarm(soundUri, "$name is now open. $description.")
        postAlarmNotification("SESSION OPEN: $name", description, symbol = "SESSION")
    }

    private fun updateConnectionLossWarning(prefs: SharedPreferences, connected: Boolean) {
        updateConnectionStatus(prefs, connected, if (!connected) "Market feed unreachable" else "")
    }

    private fun updateConnectionStatus(prefs: SharedPreferences, connected: Boolean, reason: String = "") {
        isNetworkConnected = connected
        val manager = getSystemService(NotificationManager::class.java)

        if (connected) {
            lastPriceCheckSuccessMs = System.currentTimeMillis()
            prefs.edit().remove("biquote_disconnect_started_at").remove("biquote_disconnect_warned").apply()
            try { manager.cancel(1998) } catch (_: Throwable) {}
        } else {
            val now = System.currentTimeMillis()
            val startedAt = prefs.getLong("biquote_disconnect_started_at", now)
            if (!prefs.contains("biquote_disconnect_started_at")) {
                prefs.edit().putLong("biquote_disconnect_started_at", now).apply()
            }
            // Update persistent foreground notification immediately to reflect offline/paused state
            val warningText = if (reason.isNotBlank()) "⚠️ $reason · Evaluation paused" else "⚠️ Connection lost · Background evaluation paused, reconnecting..."
            val notification = buildNotification(warningText, isWarning = true)
            manager.notify(NOTIFICATION_ID, notification)

            val enabled = when (
                val raw = prefs.all["setting_deadman_warning"]
                    ?: prefs.all["flutter.setting_deadman_warning"]
            ) {
                is Boolean -> raw
                is String -> raw.toBoolean()
                else -> true
            }
            if (enabled && now - startedAt >= TimeUnit.MINUTES.toMillis(2) &&
                !prefs.getBoolean("biquote_disconnect_warned", false)) {
                prefs.edit().putBoolean("biquote_disconnect_warned", true).apply()
                try {
                    val tone = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 65)
                    tone.startTone(ToneGenerator.TONE_PROP_BEEP, 280)
                    alarmHandler.postDelayed({ tone.release() }, 400)
                } catch (_: Exception) {}
                val warning = NotificationCompat.Builder(this, LOW_BATTERY_CHANNEL_ID)
                    .setSmallIcon(android.R.drawable.stat_notify_error)
                    .setContentTitle("Market feed connection lost")
                    .setContentText("TenX has not reached the price feed for more than 2 minutes.")
                    .setAutoCancel(true)
                    .setOnlyAlertOnce(true)
                    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                    .build()
                manager.notify(1998, warning)
            }
        }
    }

    private val ohlcCache = java.util.concurrent.ConcurrentHashMap<String, Pair<Long, JSONArray>>()

    private fun fetchOhlcBars(symbol: String, timeframe: String, limit: Int): JSONArray? {
        val cacheKey = "$symbol:$timeframe"
        val cached = ohlcCache[cacheKey]
        val now = System.currentTimeMillis()
        if (cached != null && (now - cached.first) < 10000L && cached.second.length() >= limit) {
            return cached.second
        }

        val urlStr = "https://biquote.io/api/$symbol/ohlc?interval=$timeframe&limit=$limit"
        var responseStr: String? = null
        try {
            val url = URL(urlStr)
            val conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "GET"
            conn.connectTimeout = 4000
            conn.readTimeout = 4000
            if (conn.responseCode == 200) {
                val reader = BufferedReader(InputStreamReader(conn.inputStream))
                responseStr = reader.readText()
                reader.close()
            }
            conn.disconnect()
        } catch (_: Exception) {}

        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val allowDirectIpFallback = when (
            val raw = prefs.all["setting_direct_ip_fallback"]
                ?: prefs.all["flutter.setting_direct_ip_fallback"]
        ) {
            is Boolean -> raw
            is String -> raw.toBoolean()
            else -> true
        }
        if (responseStr == null && allowDirectIpFallback) {
            try {
                val url = URL("https://142.132.248.240/api/$symbol/ohlc?interval=$timeframe&limit=$limit")
                val conn = url.openConnection() as javax.net.ssl.HttpsURLConnection
                conn.hostnameVerifier = biquoteHostnameVerifier
                conn.setRequestProperty("Host", "biquote.io")
                conn.requestMethod = "GET"
                conn.connectTimeout = 4000
                conn.readTimeout = 4000
                if (conn.responseCode == 200) {
                    val reader = BufferedReader(InputStreamReader(conn.inputStream))
                    responseStr = reader.readText()
                    reader.close()
                }
                conn.disconnect()
            } catch (_: Exception) {}
        }

        if (responseStr != null) {
            try {
                val json = JSONObject(responseStr)
                val bars = json.optJSONArray("bars")
                if (bars != null) {
                    ohlcCache[cacheKey] = Pair(now, bars)
                    return bars
                }
            } catch (_: Exception) {}
        }
        return cached?.second
    }

    private fun syncToFlutterStorage(
        prefs: SharedPreferences,
        triggeredAlert: JSONObject?,
        remainingAlerts: JSONArray
    ) {
        try {
            val nowIso = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                java.time.Instant.now().toString()
            } else {
                java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US).format(java.util.Date())
            }

            // 1. Sync to saved_alerts
            val savedAlertsKey = prefs.all.keys.firstOrNull {
                it == "saved_alerts" || it == "flutter.saved_alerts" || it.endsWith("_saved_alerts")
            }
            val savedAlertsStr = savedAlertsKey?.let { prefs.getString(it, null) }
            if (savedAlertsStr != null && savedAlertsStr.isNotEmpty()) {
                val savedAlertsArray = JSONArray(savedAlertsStr)
                var savedChanged = false

                for (i in 0 until savedAlertsArray.length()) {
                    val a = savedAlertsArray.getJSONObject(i)
                    val aId = a.optString("id")

                    if (triggeredAlert != null && aId == triggeredAlert.optString("id")) {
                        val cooldownMin = triggeredAlert.optInt("cooldownMinutes", 0)
                        if (cooldownMin > 0) {
                            a.put("isActive", true)
                            a.put("lastTriggeredAt", nowIso)
                        } else {
                            a.put("isActive", false)
                        }
                        a.put("triggeredAt", nowIso)
                        savedChanged = true
                    } else {
                        for (r in 0 until remainingAlerts.length()) {
                            val rem = remainingAlerts.getJSONObject(r)
                            if (rem.optString("id") == aId && rem.has("multiStepConfig")) {
                                a.put("multiStepConfig", rem.optJSONObject("multiStepConfig"))
                                savedChanged = true
                                break
                            }
                        }
                    }
                }

                if (savedChanged) {
                    savedAlertsKey?.let { prefs.edit().putString(it, savedAlertsArray.toString()).apply() }
                }
            }

            // 2. Sync to saved_history
            if (triggeredAlert != null) {
                val historyKey = prefs.all.keys.firstOrNull {
                    it == "saved_history" || it == "flutter.saved_history" || it.endsWith("_saved_history")
                }
                val historyStr = historyKey?.let { prefs.getString(it, null) }
                val oldHistory = if (historyStr != null && historyStr.isNotEmpty()) JSONArray(historyStr) else JSONArray()

                val historyItem = JSONObject(triggeredAlert.toString())
                historyItem.put("isActive", false)
                historyItem.put("triggeredAt", nowIso)

                val newHistory = JSONArray()
                newHistory.put(historyItem)
                for (k in 0 until oldHistory.length()) {
                    val oldItem = oldHistory.getJSONObject(k)
                    if (oldItem.optString("id") != historyItem.optString("id")) {
                        newHistory.put(oldItem)
                    }
                }

                historyKey?.let { prefs.edit().putString(it, newHistory.toString()).apply() }
            }
        } catch (e: Exception) {}
    }

    private fun isInCooldown(alert: JSONObject): Boolean {
        val cooldownMinutes = alert.optInt("cooldownMinutes", 0)
        if (cooldownMinutes <= 0) return false
        val lastTriggeredAtStr = alert.optString("lastTriggeredAt", "")
        if (lastTriggeredAtStr.isEmpty()) return false
        return try {
            val lastTriggeredTime = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                java.time.Instant.parse(lastTriggeredAtStr).toEpochMilli()
            } else {
                java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", java.util.Locale.US).parse(lastTriggeredAtStr)?.time ?: 0L
            }
            val elapsedMs = System.currentTimeMillis() - lastTriggeredTime
            elapsedMs < (cooldownMinutes * 60 * 1000L)
        } catch (e: Exception) {
            false
        }
    }

    private fun isSnoozed(alert: JSONObject, nowMs: Long): Boolean {
        val until = alert.optString("snoozedUntil", "").takeIf { it.isNotBlank() && it != "null" } ?: return false
        return try {
            val deadline = AlertDeadlineScheduler.parseTime(until) ?: return false
            nowMs < deadline
        } catch (_: Exception) { false }
    }

    private fun checkCandlestickPattern(symbol: String, timeframe: String, pattern: String): Double? {
        try {
            val bars = fetchOhlcBars(symbol, timeframe, 6) ?: return null
            if (bars.length() < 4) return null

            // Strictly evaluate closed completed candles only:
            // bars[0] is the currently forming candle (unclosed).
            // bars[1] is the latest completed closed candle (c0).
            // bars[2] is 1 candle prior (c1), bars[3] is 2 candles prior (c2).
            val c0 = bars.getJSONObject(1)
            val c1 = bars.getJSONObject(2)
            val c2 = bars.getJSONObject(3)

            val c0Open = c0.optDouble("open")
            val c0High = c0.optDouble("high")
            val c0Low = c0.optDouble("low")
            val c0Close = c0.optDouble("close")

            val c1Open = c1.optDouble("open")
            val c1High = c1.optDouble("high")
            val c1Low = c1.optDouble("low")
            val c1Close = c1.optDouble("close")

            val c2Open = c2.optDouble("open")
            val c2High = c2.optDouble("high")
            val c2Low = c2.optDouble("low")
            val c2Close = c2.optDouble("close")

            val c0Body = Math.abs(c0Close - c0Open)
            val c1Body = Math.abs(c1Close - c1Open)
            val c2Body = Math.abs(c2Close - c2Open)

            val c0Range = Math.max(0.000001, c0High - c0Low)
            val c1Range = Math.max(0.000001, c1High - c1Low)
            val c2Range = Math.max(0.000001, c2High - c2Low)

            val c0UpperShadow = c0High - Math.max(c0Open, c0Close)
            val c0LowerShadow = Math.min(c0Open, c0Close) - c0Low

            val matches = when (pattern) {
                "bullishEngulfing" -> {
                    c1Close < c1Open && c0Close > c0Open && c0Body > c1Body && c0Open <= c1Close && c0Close >= c1Open
                }
                "bearishEngulfing" -> {
                    c1Close > c1Open && c0Close < c0Open && c0Body > c1Body && c0Open >= c1Close && c0Close <= c1Open
                }
                "hammer" -> {
                    c0Body <= 0.35 * c0Range && c0LowerShadow >= 2.0 * c0Body && c0UpperShadow <= 0.15 * c0Range && (c1Close < c1Open || c0Low < c1Low)
                }
                "hangingMan" -> {
                    c0Body <= 0.35 * c0Range && c0LowerShadow >= 2.0 * c0Body && c0UpperShadow <= 0.15 * c0Range && (c1Close > c1Open || c0High > c1High)
                }
                "shootingStar" -> {
                    c0Body <= 0.35 * c0Range && c0UpperShadow >= 2.0 * c0Body && c0LowerShadow <= 0.15 * c0Range && (c1Close > c1Open || c0High > c1High)
                }
                "invertedHammer" -> {
                    c0Body <= 0.35 * c0Range && c0UpperShadow >= 2.0 * c0Body && c0LowerShadow <= 0.15 * c0Range && (c1Close < c1Open || c0Low < c1Low)
                }
                "morningStar" -> {
                    c2Close < c2Open && c2Body >= 0.45 * c2Range && c1Body <= 0.35 * c2Body && c0Close > c0Open && c0Close >= (c2Close + (c2Body * 0.5))
                }
                "eveningStar" -> {
                    c2Close > c2Open && c2Body >= 0.45 * c2Range && c1Body <= 0.35 * c2Body && c0Close < c0Open && c0Close <= (c2Open + (c2Body * 0.5))
                }
                "doji" -> {
                    c0Body <= 0.08 * c0Range
                }
                "dragonflyDoji" -> {
                    c0Body <= 0.08 * c0Range && c0UpperShadow <= 0.12 * c0Range && c0LowerShadow >= 0.65 * c0Range
                }
                "gravestoneDoji" -> {
                    c0Body <= 0.08 * c0Range && c0LowerShadow <= 0.12 * c0Range && c0UpperShadow >= 0.65 * c0Range
                }
                "piercingLine" -> {
                    c1Close < c1Open && c0Close > c0Open && c0Open <= c1Low && c0Close >= (c1Close + (c1Body * 0.5)) && c0Close <= c1Open
                }
                "darkCloudCover" -> {
                    c1Close > c1Open && c0Close < c0Open && c0Open >= c1High && c0Close <= (c1Open + (c1Body * 0.5)) && c0Close >= c1Open
                }
                "threeWhiteSoldiers" -> {
                    c2Close > c2Open && c1Close > c1Open && c0Close > c0Open &&
                    c1Close > c2Close && c0Close > c1Close &&
                    (c1Open > c2Open && c1Open < c2Close) &&
                    (c0Open > c1Open && c0Open < c1Close) &&
                    (c0UpperShadow <= 0.25 * c0Range)
                }
                "threeBlackCrows" -> {
                    c2Close < c2Open && c1Close < c1Open && c0Close < c0Open &&
                    c1Close < c2Close && c0Close < c1Close &&
                    (c1Open < c2Open && c1Open > c2Close) &&
                    (c0Open < c1Open && c0Open > c1Close) &&
                    (c0LowerShadow <= 0.25 * c0Range)
                }
                "bullishHarami" -> {
                    c1Close < c1Open && c0Close > c0Open && c0Open >= c1Close && c0Close <= c1Open && c0Body < c1Body * 0.7
                }
                "bearishHarami" -> {
                    c1Close > c1Open && c0Close < c0Open && c0Open <= c1Close && c0Close >= c1Open && c0Body < c1Body * 0.7
                }
                "tweezerBottom" -> {
                    c1Close < c1Open && c0Close > c0Open && Math.abs(c1Low - c0Low) <= (c1Low * 0.00015) && c0LowerShadow >= 0.3 * c0Range
                }
                "tweezerTop" -> {
                    c1Close > c1Open && c0Close < c0Open && Math.abs(c1High - c0High) <= (c1High * 0.00015) && c0UpperShadow >= 0.3 * c0Range
                }
                "marubozu" -> {
                    c0Body >= 0.88 * c0Range
                }
                else -> false
            }

            if (matches) {
                return c0Close
            }
        } catch (e: Exception) {}
        return null
    }

    private fun formatPatternName(pattern: String): String {
        return when (pattern) {
            "bullishEngulfing" -> "Bullish Engulfing"
            "bearishEngulfing" -> "Bearish Engulfing"
            "hammer" -> "Hammer"
            "hangingMan" -> "Hanging Man"
            "shootingStar" -> "Shooting Star"
            "invertedHammer" -> "Inverted Hammer"
            "morningStar" -> "Morning Star"
            "eveningStar" -> "Evening Star"
            "doji" -> "Standard Doji"
            "dragonflyDoji" -> "Dragonfly Doji"
            "gravestoneDoji" -> "Gravestone Doji"
            "piercingLine" -> "Piercing Line"
            "darkCloudCover" -> "Dark Cloud Cover"
            "threeWhiteSoldiers" -> "Three White Soldiers"
            "threeBlackCrows" -> "Three Black Crows"
            "bullishHarami" -> "Bullish Harami"
            "bearishHarami" -> "Bearish Harami"
            "tweezerBottom" -> "Tweezer Bottom"
            "tweezerTop" -> "Tweezer Top"
            "marubozu" -> "Marubozu Full Body"
            else -> pattern
        }
    }

    private fun postAlarmNotification(
        title: String,
        body: String,
        triggerTimestamp: Long = System.currentTimeMillis(),
        symbol: String = "",
        triggerPrice: Double = 0.0
    ) {
        val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as? android.app.KeyguardManager
        val deviceLocked = keyguard?.isKeyguardLocked == true
        if (!MainActivity.isInForeground && !deviceLocked) {
            val overlayMessage = if (triggerPrice > 0.0) {
                "Triggered at ${formatPrice(triggerPrice)}"
            } else {
                body
            }
            AlarmHudOverlay.show(this, title, overlayMessage, symbol, triggerPrice) {
                startService(Intent(this, AlertForegroundService::class.java).apply {
                    action = ACTION_DISMISS_ALARM
                })
            }
        }

        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = "com.example.alert_app.ALARM_TRIGGER"
            putExtra("symbol", symbol)
            putExtra("triggerPrice", triggerPrice)
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val dismissIntent = Intent(this, AlertForegroundService::class.java).apply {
            action = ACTION_DISMISS_ALARM
        }
        val dismissPendingIntent = PendingIntent.getService(
            this, 1002, dismissIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val timeFmt = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date(triggerTimestamp))
        val enrichedBody = "[$timeFmt] $body"

        val notificationBuilder = NotificationCompat.Builder(this, ALARM_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(enrichedBody)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setWhen(triggerTimestamp)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setContentIntent(pendingIntent)
            .setFullScreenIntent(pendingIntent, true)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "DISMISS ALARM",
                dismissPendingIntent
            )

        val notification = notificationBuilder.build()

        val manager = getSystemService(NotificationManager::class.java)
        val alarmNotifId = ALARM_NOTIFICATION_BASE_ID + Math.abs(title.hashCode() % 1000)
        manager.notify(alarmNotifId, notification)
    }

    private fun formatPrice(price: Double): String =
        java.text.DecimalFormat("#,##0.########").format(price)

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "AlertApp:PerpetualForegroundWakeLock"
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
        }
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.let {
                if (it.isHeld) it.release()
            }
        } catch (_: Exception) {}
        wakeLock = null
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)

            // Low priority channel for ongoing status
            val statusChannel = NotificationChannel(
                CHANNEL_ID,
                "Forex Market Perpetual Monitor",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps market data monitoring and price alerts active when screen is off"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            manager.createNotificationChannel(statusChannel)

            // High priority channel for ringing alerts
            val alarmChannel = NotificationChannel(
                ALARM_CHANNEL_ID,
                "Forex Price Alarms",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Loud price alerts that wake screen and trigger alarms"
                setShowBadge(true)
                enableVibration(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            manager.createNotificationChannel(alarmChannel)

            val lowBatteryChannel = NotificationChannel(
                LOW_BATTERY_CHANNEL_ID,
                "Low Battery Protection",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "A quiet warning when background market monitoring enters battery protection"
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            manager.createNotificationChannel(lowBatteryChannel)
        }
    }

    private fun postLowBatteryWarning(level: Int) {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 1999, launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val notification = NotificationCompat.Builder(this, LOW_BATTERY_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_low_battery)
            .setContentTitle("TenX battery protection active")
            .setContentText("Battery is at $level%. Background monitoring is reducing unnecessary work.")
            .setStyle(NotificationCompat.BigTextStyle().bigText(
                "Battery is at $level%. TenX is conserving power while continuing alert monitoring."
            ))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .build()
        getSystemService(NotificationManager::class.java).notify(LOW_BATTERY_NOTIFICATION_ID, notification)
    }

    private fun buildNotification(contentText: String, isWarning: Boolean = false): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        lastNotificationText = contentText
        val title = if (isWarning || !isNetworkConnected) {
            "⚠️ TenX Monitor — Connection Lost"
        } else {
            "Forex Alert Tracker Active"
        }

        val text = if (!isNetworkConnected && !isWarning) {
            "Connection lost · Background evaluation paused, retrying..."
        } else {
            contentText
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(if (isWarning || !isNetworkConnected) android.R.drawable.stat_notify_error else android.R.drawable.ic_lock_idle_alarm)
            .setOngoing(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(pendingIntent)
            .setPriority(if (isWarning || !isNetworkConnected) NotificationCompat.PRIORITY_DEFAULT else NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun formatIndicatorSummary(config: JSONObject?): String {
        if (config == null) return "Technical Indicator Alert"
        val indType = config.optString("indicatorType")
        val cond = config.optString("condition")
        val params = config.optJSONObject("params") ?: JSONObject()
        return when (indType) {
            "rsi" -> {
                val period = params.optInt("period", 14)
                val level = params.optDouble("level", 30.0)
                "RSI($period) $cond (Level: $level)"
            }
            "macd" -> {
                val fast = params.optInt("fast", 12)
                val slow = params.optInt("slow", 26)
                val signal = params.optInt("signal", 9)
                "MACD($fast/$slow/$signal) $cond"
            }
            "maCross" -> {
                val fastP = params.optInt("fastPeriod", 50)
                val slowP = params.optInt("slowPeriod", 200)
                val maType = params.optString("maType", "EMA")
                "$maType($fastP/$slowP) $cond"
            }
            "bollingerBands" -> {
                val period = params.optInt("period", 20)
                val stdDev = params.optDouble("stdDev", 2.0)
                "Bollinger Bands($period, ${stdDev}x) $cond"
            }
            "stochastic" -> {
                val kP = params.optInt("kPeriod", 14)
                val dP = params.optInt("dPeriod", 3)
                "Stochastic($kP/$dP) $cond"
            }
            "supertrend" -> {
                val period = params.optInt("period", 10)
                val mult = params.optDouble("multiplier", 3.0)
                "Supertrend($period, ${mult}x) $cond"
            }
            else -> "$indType $cond"
        }
    }

    private fun checkTechnicalIndicator(symbol: String, timeframe: String, config: JSONObject): Double? {
        try {
            val indicatorType = config.optString("indicatorType")
            val condition = config.optString("condition")
            val params = config.optJSONObject("params") ?: JSONObject()

            // Fetch up to 250 bars to support slow MAs (e.g., 200 EMA) via throttled cache
            val bars = fetchOhlcBars(symbol, timeframe, 250) ?: return null
            if (bars.length() < 15) return null

                val closes = mutableListOf<Double>()
                val highs = mutableListOf<Double>()
                val lows = mutableListOf<Double>()
                val opens = mutableListOf<Double>()
                for (i in bars.length() - 1 downTo 0) {
                    val b = bars.getJSONObject(i)
                    closes.add(b.optDouble("close"))
                    highs.add(b.optDouble("high"))
                    lows.add(b.optDouble("low"))
                    opens.add(b.optDouble("open"))
                }
                val latestClose = closes.last()

                var isTriggered = false
                when (indicatorType) {
                    "rsi" -> {
                        val period = params.optInt("period", 14)
                        val source = params.optString("source", "Close")
                        val smoothingType = params.optString("smoothingType", "RMA")
                        val level = params.optDouble("level", 30.0)
                        val overbought = params.optDouble("overbought", 70.0)
                        val oversold = params.optDouble("oversold", 30.0)
                        val priceSeries = extractPrices(opens, highs, lows, closes, source)

                        if (priceSeries.size > period + 2) {
                            val rsiList = calculateRsi(priceSeries, period, smoothingType)
                            if (rsiList.size >= 2) {
                                val curr = rsiList.last()
                                val prev = rsiList[rsiList.size - 2]

                                if (condition == "crossesAboveSignalMa" || condition == "crossesBelowSignalMa") {
                                    val signalMaPeriod = params.optInt("signalMaPeriod", 9)
                                    val signalMaType = params.optString("signalMaType", "EMA")
                                    if (rsiList.size >= signalMaPeriod + 2) {
                                        val maSeries = calculateMa(rsiList, signalMaPeriod, signalMaType)
                                        if (maSeries.size >= 2) {
                                            val currMa = maSeries.last()
                                            val prevMa = maSeries[maSeries.size - 2]
                                            isTriggered = if (condition == "crossesAboveSignalMa") {
                                                prev <= prevMa && curr > currMa
                                            } else {
                                                prev >= prevMa && curr < currMa
                                            }
                                        }
                                    }
                                } else {
                                    isTriggered = when (condition) {
                                        "crossesAbove", "crossesAboveLevel" -> prev < level && curr >= level
                                        "crossesBelow", "crossesBelowLevel" -> prev > level && curr <= level
                                        "crossesBelowOversold" -> prev >= oversold && curr < oversold
                                        "crossesAboveOversold" -> prev <= oversold && curr > oversold
                                        "crossesAboveOverbought" -> prev <= overbought && curr > overbought
                                        "crossesBelowOverbought" -> prev >= overbought && curr < overbought
                                        "overboughtEnter" -> prev <= overbought && curr > overbought
                                        "oversoldEnter" -> prev >= oversold && curr < oversold
                                        "crossesAboveCenterline" -> prev <= 50.0 && curr > 50.0
                                        "crossesBelowCenterline" -> prev >= 50.0 && curr < 50.0
                                        "centerlineCross" -> (prev < 50.0 && curr >= 50.0) || (prev > 50.0 && curr <= 50.0)
                                        "inOversold" -> curr < oversold
                                        "inOverbought" -> curr > overbought
                                        "inBandRange" -> curr in oversold..overbought
                                        "outsideBandRange" -> curr < oversold || curr > overbought
                                        "rsiTurningUp" -> rsiList.size >= 3 && prev <= rsiList[rsiList.size - 3] && curr > prev
                                        "rsiTurningDown" -> rsiList.size >= 3 && prev >= rsiList[rsiList.size - 3] && curr < prev
                                        else -> false
                                    }
                                }
                            }
                        }
                    }
                    "macd" -> {
                        val fast = params.optInt("fast", 12)
                        val slow = params.optInt("slow", 26)
                        val signal = params.optInt("signal", 9)
                        val source = params.optString("source", "Close")
                        val fastMaType = params.optString("fastMaType", "EMA")
                        val slowMaType = params.optString("slowMaType", "EMA")
                        val signalMaType = params.optString("signalMaType", "EMA")
                        val priceSeries = extractPrices(opens, highs, lows, closes, source)

                        if (priceSeries.size >= slow + signal + 2) {
                            val macdData = calculateMacd(priceSeries, fast, slow, signal, fastMaType, slowMaType, signalMaType)
                            val macdLine = macdData.macd
                            val signalLine = macdData.signal
                            val hist = macdData.histogram

                            if (macdLine.size >= 2 && signalLine.size >= 2) {
                                val currM = macdLine.last()
                                val prevM = macdLine[macdLine.size - 2]
                                val currS = signalLine.last()
                                val prevS = signalLine[signalLine.size - 2]
                                val currH = if (hist.isNotEmpty()) hist.last() else 0.0
                                val prevH = if (hist.size >= 2) hist[hist.size - 2] else 0.0

                                isTriggered = when (condition) {
                                    "bullishSignalCross" -> prevM <= prevS && currM > currS
                                    "bearishSignalCross" -> prevM >= prevS && currM < currS
                                    "zeroLineCrossAbove", "zeroCrossAbove" -> prevM <= 0.0 && currM > 0.0
                                    "zeroLineCrossBelow", "zeroCrossBelow" -> prevM >= 0.0 && currM < 0.0
                                    "zeroLineCross" -> (prevM <= 0.0 && currM > 0.0) || (prevM >= 0.0 && currM < 0.0)
                                    "signalZeroCrossAbove" -> prevS <= 0.0 && currS > 0.0
                                    "signalZeroCrossBelow" -> prevS >= 0.0 && currS < 0.0
                                    "histogramFlipPositive" -> prevH <= 0.0 && currH > 0.0
                                    "histogramFlipNegative" -> prevH >= 0.0 && currH < 0.0
                                    "macdAboveSignal" -> currM > currS
                                    "macdBelowSignal" -> currM < currS
                                    "macdAboveZero" -> currM > 0.0
                                    "macdBelowZero" -> currM < 0.0
                                    "histogramPositive" -> currH > 0.0
                                    "histogramNegative" -> currH < 0.0
                                    "histogramTurningUp" -> hist.size >= 3 && prevH <= hist[hist.size - 3] && currH > prevH
                                    "histogramTurningDown" -> hist.size >= 3 && prevH >= hist[hist.size - 3] && currH < prevH
                                    "macdTurningUp" -> macdLine.size >= 3 && prevM <= macdLine[macdLine.size - 3] && currM > prevM
                                    "macdTurningDown" -> macdLine.size >= 3 && prevM >= macdLine[macdLine.size - 3] && currM < prevM
                                    else -> false
                                }
                            }
                        }
                    }
                    "maCross" -> {
                        val fastP = params.optInt("fastPeriod", 50)
                        val slowP = params.optInt("slowPeriod", 200)
                        val maType = params.optString("maType", "EMA")
                        val fastMaType = params.optString("fastMaType", maType)
                        val slowMaType = params.optString("slowMaType", maType)
                        val source = params.optString("source", "Close")
                        val priceSeries = extractPrices(opens, highs, lows, closes, source)

                        val maxP = Math.max(fastP, slowP)
                        if (priceSeries.size >= maxP + 2) {
                            val fastMa = calculateMa(priceSeries, fastP, fastMaType)
                            val slowMa = calculateMa(priceSeries, slowP, slowMaType)
                            if (fastMa.size >= 2 && slowMa.size >= 2) {
                                val currF = fastMa.last()
                                val prevF = fastMa[fastMa.size - 2]
                                val currS = slowMa.last()
                                val prevS = slowMa[slowMa.size - 2]
                                val currP = priceSeries.last()
                                val prevP = priceSeries[priceSeries.size - 2]

                                isTriggered = when (condition) {
                                    "goldenCross", "fastCrossesAboveSlow" -> prevF <= prevS && currF > currS
                                    "deathCross", "fastCrossesBelowSlow" -> prevF >= prevS && currF < currS
                                    "maCross" -> (prevF <= prevS && currF > currS) || (prevF >= prevS && currF < currS)
                                    "priceCrossesAbove", "priceCrossesAboveFast" -> prevP <= prevF && currP > currF
                                    "priceCrossesBelow", "priceCrossesBelowFast" -> prevP >= prevF && currP < currF
                                    "priceCrossesAboveSlow" -> prevP <= prevS && currP > currS
                                    "priceCrossesBelowSlow" -> prevP >= prevS && currP < currS
                                    "fastAboveSlow" -> currF > currS
                                    "fastBelowSlow" -> currF < currS
                                    "priceAboveFast" -> currP > currF
                                    "priceBelowFast" -> currP < currF
                                    "priceAboveSlow" -> currP > currS
                                    "priceBelowSlow" -> currP < currS
                                    "priceAboveBoth" -> currP > currF && currP > currS
                                    "priceBelowBoth" -> currP < currF && currP < currS
                                    "priceBetweenMAs" -> currP > Math.min(currF, currS) && currP < Math.max(currF, currS)
                                    "fastTurningUp" -> fastMa.size >= 3 && prevF <= fastMa[fastMa.size - 3] && currF > prevF
                                    "fastTurningDown" -> fastMa.size >= 3 && prevF >= fastMa[fastMa.size - 3] && currF < prevF
                                    "slowTurningUp" -> slowMa.size >= 3 && prevS <= slowMa[slowMa.size - 3] && currS > prevS
                                    "slowTurningDown" -> slowMa.size >= 3 && prevS >= slowMa[slowMa.size - 3] && currS < prevS
                                    else -> false
                                }
                            }
                        }
                    }
                    "bollingerBands" -> {
                        val period = params.optInt("period", 20)
                        val stdMult = params.optDouble("stdDev", 2.0)
                        val source = params.optString("source", "Close")
                        val maType = params.optString("maType", "SMA")
                        val squeezeThreshold = params.optDouble("squeezeThreshold", 0.015)
                        val priceSeries = extractPrices(opens, highs, lows, closes, source)

                        if (priceSeries.size >= period + 2) {
                            val bb = calculateBollingerBands(priceSeries, period, stdMult, maType)
                            if (bb.upper.size >= 2) {
                                val currUpper = bb.upper.last()
                                val prevUpper = bb.upper[bb.upper.size - 2]
                                val currLower = bb.lower.last()
                                val prevLower = bb.lower[bb.lower.size - 2]
                                val currMid = bb.middle.last()
                                val prevMid = bb.middle[bb.middle.size - 2]
                                val currBw = bb.bandwidth.last()
                                val prevBw = bb.bandwidth[bb.bandwidth.size - 2]
                                val currPb = bb.percentB.last()
                                val prevPb = bb.percentB[bb.percentB.size - 2]

                                val currPrice = priceSeries.last()
                                val prevPrice = priceSeries[priceSeries.size - 2]

                                isTriggered = when (condition) {
                                    "upperBandTouch", "priceCrossesAboveUpper" -> prevPrice <= prevUpper && currPrice > currUpper
                                    "priceCrossesBelowUpper" -> prevPrice >= prevUpper && currPrice < currUpper
                                    "lowerBandTouch", "priceCrossesBelowLower" -> prevPrice >= prevLower && currPrice < currLower
                                    "priceCrossesAboveLower" -> prevPrice <= prevLower && currPrice > currLower
                                    "middleBandCrossAbove" -> prevPrice <= prevMid && currPrice > currMid
                                    "middleBandCrossBelow" -> prevPrice >= prevMid && currPrice < currMid
                                    "middleBandCross" -> (prevPrice <= prevMid && currPrice > currMid) || (prevPrice >= prevMid && currPrice < currMid)
                                    "priceAboveUpper" -> currPrice > currUpper
                                    "priceBelowLower" -> currPrice < currLower
                                    "priceInsideBands" -> currPrice in currLower..currUpper
                                    "priceInUpperHalf" -> currPrice > currMid && currPrice <= currUpper
                                    "priceInLowerHalf" -> currPrice < currMid && currPrice >= currLower
                                    "squeeze" -> currBw <= squeezeThreshold
                                    "squeezeBreakout" -> prevBw <= squeezeThreshold && currBw > squeezeThreshold
                                    "bandwidthExpanding" -> currBw > prevBw
                                    "bandwidthContracting" -> currBw < prevBw
                                    "percentBCrossesAbove80" -> prevPb <= 0.8 && currPb > 0.8
                                    "percentBCrossesBelow20" -> prevPb >= 0.2 && currPb < 0.2
                                    "percentBCrossesAboveCenter" -> prevPb <= 0.5 && currPb > 0.5
                                    "percentBCrossesBelowCenter" -> prevPb >= 0.5 && currPb < 0.5
                                    else -> false
                                }
                            }
                        }
                    }
                    "stochastic" -> {
                        val kPeriod = params.optInt("kPeriod", 14)
                        val kSlowing = params.optInt("kSlowing", 3)
                        val dPeriod = params.optInt("dPeriod", 3)
                        val dMaType = params.optString("dMaType", "SMA")
                        val oversold = params.optDouble("oversoldLevel", params.optDouble("oversold", 20.0))
                        val overbought = params.optDouble("overboughtLevel", params.optDouble("overbought", 80.0))

                        if (closes.size >= kPeriod + kSlowing + dPeriod + 2) {
                            val stoch = calculateStochastic(highs, lows, closes, kPeriod, kSlowing, dPeriod, dMaType)
                            val kList = stoch.k
                            val dList = stoch.d
                            if (kList.size >= 2 && dList.size >= 2) {
                                val currK = kList.last()
                                val prevK = kList[kList.size - 2]
                                val currD = dList.last()
                                val prevD = dList[dList.size - 2]

                                isTriggered = when (condition) {
                                    "bullishCross", "kCrossesAboveD" -> prevK <= prevD && currK > currD
                                    "bearishCross", "kCrossesBelowD" -> prevK >= prevD && currK < currD
                                    "bullishOversoldCross" -> prevK <= prevD && currK > currD && currK <= oversold
                                    "bearishOverboughtCross" -> prevK >= prevD && currK < currD && currK >= overbought
                                    "kCrossesAboveOversold", "crossesAbove20" -> prevK <= oversold && currK > oversold
                                    "kCrossesBelowOversold" -> prevK >= oversold && currK < oversold
                                    "kCrossesAboveOverbought" -> prevK <= overbought && currK > overbought
                                    "kCrossesBelowOverbought", "crossesBelow80" -> prevK >= overbought && currK < overbought
                                    "kCrossesAbove50" -> prevK <= 50.0 && currK > 50.0
                                    "kCrossesBelow50" -> prevK >= 50.0 && currK < 50.0
                                    "centerlineCross" -> (prevK <= 50.0 && currK > 50.0) || (prevK >= 50.0 && currK < 50.0)
                                    "kAboveD" -> currK > currD
                                    "kBelowD" -> currK < currD
                                    "inOversold" -> currK < oversold
                                    "inOverbought" -> currK > overbought
                                    "inNeutralBand" -> currK in oversold..overbought
                                    "kTurningUp" -> kList.size >= 3 && prevK <= kList[kList.size - 3] && currK > prevK
                                    "kTurningDown" -> kList.size >= 3 && prevK >= kList[kList.size - 3] && currK < prevK
                                    "dTurningUp" -> dList.size >= 3 && prevD <= dList[dList.size - 3] && currD > prevD
                                    "dTurningDown" -> dList.size >= 3 && prevD >= dList[dList.size - 3] && currD < prevD
                                    else -> false
                                }
                            }
                        }
                    }
                    "supertrend" -> {
                        val period = params.optInt("period", 10)
                        val mult = params.optDouble("multiplier", 3.0)
                        val source = params.optString("source", "HL2")
                        val atrSmoothing = params.optString("atrSmoothing", "RMA")
                        val distThreshold = params.optDouble("distanceThreshold", 1.0) / 100.0

                        if (closes.size >= period + 5) {
                            val stResult = calculateSupertrend(opens, highs, lows, closes, period, mult, source, atrSmoothing)
                            val trends = stResult.trends
                            val trails = stResult.trails
                            if (trends.size >= 2 && trails.size >= 2) {
                                val currTrend = trends.last()
                                val prevTrend = trends[trends.size - 2]
                                val currTrail = trails.last()
                                val prevTrail = trails[trails.size - 2]

                                val currClose = closes.last()
                                val prevClose = closes[closes.size - 2]
                                val currOpen = opens.last()
                                val currHigh = highs.last()
                                val currLow = lows.last()
                                val prevHigh = highs[highs.size - 2]
                                val prevLow = lows[lows.size - 2]

                                val currDistanceRatio = Math.abs(currClose - currTrail) / (if (currClose == 0.0) 1.0 else currClose)

                                isTriggered = when (condition) {
                                    "bullishFlip" -> prevTrend == -1 && currTrend == 1
                                    "bearishFlip" -> prevTrend == 1 && currTrend == -1
                                    "trendFlip" -> prevTrend != currTrend
                                    "priceCrossesAboveTrail" -> (prevClose <= prevTrail && currClose > currTrail) || (prevTrend == -1 && currTrend == 1)
                                    "priceCrossesBelowTrail" -> (prevClose >= prevTrail && currClose < currTrail) || (prevTrend == 1 && currTrend == -1)
                                    "priceTouchesTrail" -> currLow <= currTrail && currHigh >= currTrail
                                    "priceBouncesOffTrail" -> {
                                        if (currTrend == 1) {
                                            (currLow <= currTrail || prevLow <= prevTrail) && currClose > currTrail && currClose >= currOpen
                                        } else {
                                            (currHigh >= currTrail || prevHigh >= prevTrail) && currClose < currTrail && currClose <= currOpen
                                        }
                                    }
                                    "inBullishTrend" -> currTrend == 1
                                    "inBearishTrend" -> currTrend == -1
                                    "priceAboveTrail" -> currClose > currTrail
                                    "priceBelowTrail" -> currClose < currTrail
                                    "trailRising" -> currTrail > prevTrail
                                    "trailFalling" -> currTrail < prevTrail
                                    "trailFlat" -> currTrail == prevTrail
                                    "priceDistanceGreaterThan" -> currDistanceRatio >= distThreshold
                                    "priceDistanceLessThan" -> currDistanceRatio <= distThreshold
                                    else -> false
                                }
                            }
                        }
                    }
                }

                if (isTriggered) {
                    return latestClose
                }
        } catch (e: Exception) {}
        return null
    }

    private fun extractPrices(
        opens: List<Double>,
        highs: List<Double>,
        lows: List<Double>,
        closes: List<Double>,
        source: String?
    ): List<Double> {
        val src = source?.lowercase() ?: "close"
        return when (src) {
            "open" -> opens
            "high" -> highs
            "low" -> lows
            "hl2" -> highs.indices.map { (highs[it] + lows[it]) / 2.0 }
            "hlc3" -> highs.indices.map { (highs[it] + lows[it] + closes[it]) / 3.0 }
            "ohlc4" -> highs.indices.map { (opens[it] + highs[it] + lows[it] + closes[it]) / 4.0 }
            else -> closes
        }
    }

    private fun calculateRsi(prices: List<Double>, period: Int, smoothingType: String = "RMA"): List<Double> {
        val rsi = mutableListOf<Double>()
        if (prices.size <= period) return rsi
        var gainSum = 0.0
        var lossSum = 0.0
        for (i in 1..period) {
            val change = prices[i] - prices[i - 1]
            if (change > 0) gainSum += change
            if (change < 0) lossSum += Math.abs(change)
        }
        var avgGain = gainSum / period
        var avgLoss = lossSum / period
        var rs = if (avgLoss == 0.0) 100.0 else avgGain / avgLoss
        rsi.add(100.0 - (100.0 / (1.0 + rs)))

        val k = 2.0 / (period + 1)

        for (i in period + 1 until prices.size) {
            val change = prices[i] - prices[i - 1]
            val gain = if (change > 0) change else 0.0
            val loss = if (change < 0) Math.abs(change) else 0.0

            if (smoothingType.equals("EMA", ignoreCase = true)) {
                avgGain = (gain * k) + (avgGain * (1.0 - k))
                avgLoss = (loss * k) + (avgLoss * (1.0 - k))
            } else if (smoothingType.equals("SMA", ignoreCase = true)) {
                var gSum = 0.0
                var lSum = 0.0
                for (j in (i - period + 1)..i) {
                    val ch = prices[j] - prices[j - 1]
                    if (ch > 0) gSum += ch
                    if (ch < 0) lSum += Math.abs(ch)
                }
                avgGain = gSum / period
                avgLoss = lSum / period
            } else if (smoothingType.equals("WMA", ignoreCase = true)) {
                var gSum = 0.0
                var lSum = 0.0
                val denom = (period * (period + 1)) / 2.0
                for (j in 0 until period) {
                    val idx = i - period + 1 + j
                    val ch = prices[idx] - prices[idx - 1]
                    val weight = j + 1
                    if (ch > 0) gSum += ch * weight
                    if (ch < 0) lSum += Math.abs(ch) * weight
                }
                avgGain = gSum / denom
                avgLoss = lSum / denom
            } else {
                // Default Wilder's RMA
                avgGain = (avgGain * (period - 1) + gain) / period
                avgLoss = (avgLoss * (period - 1) + loss) / period
            }

            rs = if (avgLoss == 0.0) 100.0 else avgGain / avgLoss
            rsi.add(100.0 - (100.0 / (1.0 + rs)))
        }
        return rsi
    }

    private fun calculateSma(values: List<Double>, period: Int): List<Double> {
        val sma = mutableListOf<Double>()
        if (values.size < period) return sma
        var sum = 0.0
        for (i in 0 until period) sum += values[i]
        sma.add(sum / period)
        for (i in period until values.size) {
            sum += values[i] - values[i - period]
            sma.add(sum / period)
        }
        return sma
    }

    private fun calculateEma(values: List<Double>, period: Int): List<Double> {
        val ema = mutableListOf<Double>()
        if (values.size < period) return ema
        val k = 2.0 / (period + 1)
        var sum = 0.0
        for (i in 0 until period) sum += values[i]
        var curr = sum / period
        ema.add(curr)
        for (i in period until values.size) {
            curr = (values[i] * k) + (curr * (1.0 - k))
            ema.add(curr)
        }
        return ema
    }

    private fun calculateWma(values: List<Double>, period: Int): List<Double> {
        val wma = mutableListOf<Double>()
        if (values.size < period) return wma
        val denominator = (period * (period + 1)) / 2.0
        for (i in period - 1 until values.size) {
            var sum = 0.0
            for (j in 0 until period) {
                sum += values[i - period + 1 + j] * (j + 1)
            }
            wma.add(sum / denominator)
        }
        return wma
    }

    private fun calculateMa(values: List<Double>, period: Int, maType: String): List<Double> {
        return if (maType.equals("SMA", ignoreCase = true)) {
            calculateSma(values, period)
        } else if (maType.equals("WMA", ignoreCase = true)) {
            calculateWma(values, period)
        } else {
            calculateEma(values, period)
        }
    }

    data class MacdResult(
        val macd: List<Double>,
        val signal: List<Double>,
        val histogram: List<Double>
    )

    private fun calculateMacd(
        prices: List<Double>,
        fastPeriod: Int,
        slowPeriod: Int,
        signalPeriod: Int,
        fastMaType: String = "EMA",
        slowMaType: String = "EMA",
        signalMaType: String = "EMA"
    ): MacdResult {
        val fastMa = calculateMa(prices, fastPeriod, fastMaType)
        val slowMa = calculateMa(prices, slowPeriod, slowMaType)
        if (fastMa.isEmpty() || slowMa.isEmpty()) {
            return MacdResult(emptyList(), emptyList(), emptyList())
        }

        val offset = fastMa.size - slowMa.size
        if (offset < 0) return MacdResult(emptyList(), emptyList(), emptyList())

        val macdLine = mutableListOf<Double>()
        for (i in 0 until slowMa.size) {
            macdLine.add(fastMa[i + offset] - slowMa[i])
        }

        val signalLine = calculateMa(macdLine, signalPeriod, signalMaType)
        val sigOffset = macdLine.size - signalLine.size
        if (sigOffset < 0) return MacdResult(emptyList(), emptyList(), emptyList())

        val trimmedMacd = macdLine.subList(sigOffset, macdLine.size)
        val histogram = mutableListOf<Double>()
        for (i in 0 until signalLine.size) {
            histogram.add(trimmedMacd[i] - signalLine[i])
        }

        return MacdResult(trimmedMacd, signalLine, histogram)
    }

    data class BollingerBandsResult(
        val upper: List<Double>,
        val middle: List<Double>,
        val lower: List<Double>,
        val bandwidth: List<Double>,
        val percentB: List<Double>
    )

    private fun calculateBollingerBands(
        prices: List<Double>,
        period: Int,
        stdDevMultiplier: Double,
        maType: String = "SMA"
    ): BollingerBandsResult {
        if (prices.size < period) {
            return BollingerBandsResult(emptyList(), emptyList(), emptyList(), emptyList(), emptyList())
        }
        val middleMa = calculateMa(prices, period, maType)
        val upper = mutableListOf<Double>()
        val middle = mutableListOf<Double>()
        val lower = mutableListOf<Double>()
        val bandwidth = mutableListOf<Double>()
        val percentB = mutableListOf<Double>()

        val offset = prices.size - middleMa.size

        for (i in 0 until middleMa.size) {
            val priceIdx = i + offset
            val slice = prices.subList(priceIdx - period + 1, priceIdx + 1)
            val mean = middleMa[i]

            var varianceSum = 0.0
            for (p in slice) {
                varianceSum += Math.pow(p - mean, 2.0)
            }
            val stdDev = Math.sqrt(varianceSum / period)

            val up = mean + (stdDev * stdDevMultiplier)
            val low = mean - (stdDev * stdDevMultiplier)
            val bw = if (mean != 0.0) (up - low) / mean else 0.0
            val bandWidthDiff = up - low
            val pb = if (bandWidthDiff != 0.0) (prices[priceIdx] - low) / bandWidthDiff else 0.5

            upper.add(up)
            middle.add(mean)
            lower.add(low)
            bandwidth.add(bw)
            percentB.add(pb)
        }
        return BollingerBandsResult(upper, middle, lower, bandwidth, percentB)
    }

    data class StochasticResult(
        val k: List<Double>,
        val d: List<Double>
    )

    private fun calculateStochastic(
        highs: List<Double>,
        lows: List<Double>,
        closes: List<Double>,
        kPeriod: Int,
        kSlowing: Int = 3,
        dPeriod: Int = 3,
        dMaType: String = "SMA"
    ): StochasticResult {
        if (closes.size < kPeriod) {
            return StochasticResult(emptyList(), emptyList())
        }
        val rawK = mutableListOf<Double>()
        for (i in kPeriod - 1 until closes.size) {
            val highSlice = highs.subList(i - kPeriod + 1, i + 1)
            val lowSlice = lows.subList(i - kPeriod + 1, i + 1)
            val highest = highSlice.maxOrNull() ?: closes[i]
            val lowest = lowSlice.minOrNull() ?: closes[i]
            val range = highest - lowest
            val k = if (range == 0.0) 50.0 else ((closes[i] - lowest) / range) * 100.0
            rawK.add(k)
        }

        val smoothedK = if (kSlowing > 1) calculateSma(rawK, kSlowing) else rawK
        if (smoothedK.isEmpty()) return StochasticResult(emptyList(), emptyList())

        val dSeries = calculateMa(smoothedK, dPeriod, dMaType)
        val offset = smoothedK.size - dSeries.size
        if (offset < 0) return StochasticResult(emptyList(), emptyList())

        val trimmedK = smoothedK.subList(offset, smoothedK.size)
        return StochasticResult(trimmedK, dSeries)
    }

    private fun calculateAtr(highs: List<Double>, lows: List<Double>, closes: List<Double>, period: Int, smoothing: String = "RMA"): List<Double> {
        val n = closes.size
        val tr = mutableListOf<Double>()
        for (i in 0 until n) {
            if (i == 0) {
                tr.add(highs[i] - lows[i])
            } else {
                val hl = highs[i] - lows[i]
                val hc = Math.abs(highs[i] - closes[i - 1])
                val lc = Math.abs(lows[i] - closes[i - 1])
                tr.add(Math.max(hl, Math.max(hc, lc)))
            }
        }

        if (smoothing.equals("SMA", ignoreCase = true)) {
            val sma = calculateSma(tr, period)
            val pad = List(n - sma.size) { if (sma.isNotEmpty()) sma[0] else 0.0 }
            return pad + sma
        } else if (smoothing.equals("EMA", ignoreCase = true)) {
            val ema = calculateEma(tr, period)
            val pad = List(n - ema.size) { if (ema.isNotEmpty()) ema[0] else 0.0 }
            return pad + ema
        } else if (smoothing.equals("WMA", ignoreCase = true)) {
            val wma = calculateWma(tr, period)
            val pad = List(n - wma.size) { if (wma.isNotEmpty()) wma[0] else 0.0 }
            return pad + wma
        }

        // Default Wilder's RMA
        val atr = mutableListOf<Double>()
        var sum = 0.0
        for (i in 0 until n) {
            if (i < period) {
                sum += tr[i]
                atr.add(sum / (i + 1))
            } else {
                val cur = (atr[i - 1] * (period - 1) + tr[i]) / period
                atr.add(cur)
            }
        }
        return atr
    }

    data class SupertrendResult(
        val trends: List<Int>,
        val trails: List<Double>
    )

    private fun calculateSupertrend(
        opens: List<Double>,
        highs: List<Double>,
        lows: List<Double>,
        closes: List<Double>,
        period: Int,
        multiplier: Double,
        source: String = "HL2",
        atrSmoothing: String = "RMA"
    ): SupertrendResult {
        val n = closes.size
        val atr = calculateAtr(highs, lows, closes, period, atrSmoothing)
        if (atr.size < n) return SupertrendResult(emptyList(), emptyList())

        val trends = mutableListOf<Int>()
        val trails = mutableListOf<Double>()
        var upperBand = 0.0
        var lowerBand = 0.0
        var trend = 1

        for (i in 0 until n) {
            val basePrice = when (source.lowercase()) {
                "close" -> closes[i]
                "open" -> opens[i]
                "high" -> highs[i]
                "low" -> lows[i]
                "hlc3" -> (highs[i] + lows[i] + closes[i]) / 3.0
                "ohlc4" -> (opens[i] + highs[i] + lows[i] + closes[i]) / 4.0
                else -> (highs[i] + lows[i]) / 2.0
            }
            val curAtr = atr[i]
            val basicUpper = basePrice + (multiplier * curAtr)
            val basicLower = basePrice - (multiplier * curAtr)

            if (i == 0) {
                upperBand = basicUpper
                lowerBand = basicLower
                trend = 1
            } else {
                val prevClose = closes[i - 1]
                lowerBand = if (basicLower > lowerBand || prevClose < lowerBand) basicLower else lowerBand
                upperBand = if (basicUpper < upperBand || prevClose > upperBand) basicUpper else upperBand

                if (trend == 1 && closes[i] < lowerBand) {
                    trend = -1
                } else if (trend == -1 && closes[i] > upperBand) {
                    trend = 1
                }
            }
            trends.add(trend)
            trails.add(if (trend == 1) lowerBand else upperBand)
        }
        return SupertrendResult(trends, trails)
    }

    override fun onDestroy() {
        unregisterNetworkCallback()
        isServiceRunning = false
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_MONITOR_RUNNING, false)
            .apply()
        if (!isExplicitStop) {
            // Immediate resurrection if destroyed by OS or low memory
            AlarmWatchdog.scheduleNextWatchdog(applicationContext, 2000L)
        }
        scheduler?.shutdownNow()
        scheduler = null
        releaseWakeLock()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
