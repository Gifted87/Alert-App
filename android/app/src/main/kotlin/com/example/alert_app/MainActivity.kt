package com.example.alert_app

import android.app.KeyguardManager
import android.app.NotificationManager
import android.app.NotificationChannel
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import android.view.WindowInsets
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import java.io.File
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        @Volatile var isInForeground: Boolean = false
    }

    private val CHANNEL = "com.example.alert_app/alarm"
    private var previewPlayer: MediaPlayer? = null
    private val previewHandler = Handler(Looper.getMainLooper())
    private var previewRunnable: Runnable? = null
    private var pendingPickAudioResult: MethodChannel.Result? = null
    private val REQUEST_CODE_PICK_AUDIO = 9021
    private var pendingAuthResult: MethodChannel.Result? = null
    private val REQUEST_CODE_AUTH = 9022
    private var mainMethodChannel: MethodChannel? = null
    private var pendingAlarm: Map<String, Any>? = null
    private var pendingCameraPermissionResult: MethodChannel.Result? = null
    private var pendingExportResult: MethodChannel.Result? = null
    private var pendingExportContent: String? = null
    private val REQUEST_CODE_SAVE_EXPORT = 9023
    private var alertWindowMode = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Ensure lock screen display flags are set
        configureLockScreenDisplay()

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        mainMethodChannel = channel
        if (intent?.action == "com.example.alert_app.ALARM_TRIGGER" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            val wake = getSharedPreferences(AlertForegroundService.PREFS_NAME, Context.MODE_PRIVATE)
                .getString("setting_screen_wakeup", "true") == "true"
            setTurnScreenOn(wake)
        }
        handleAlarmIntent(intent)

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "shareText" -> {
                    val text = call.argument<String>("text")
                    if (text.isNullOrBlank()) {
                        result.error("SHARE_EMPTY", "Share content is empty", null)
                    } else {
                        try {
                            val send = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_TEXT, text)
                            }
                            startActivity(Intent.createChooser(send, "Share diagnostic report"))
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SHARE_FAILED", e.localizedMessage, null)
                        }
                    }
                }
                "consumePendingAlarm" -> {
                    val alarm = pendingAlarm
                    pendingAlarm = null
                    result.success(alarm)
                }
                "saveExportFile" -> {
                    if (pendingExportResult != null) {
                        result.error("EXPORT_BUSY", "Another export is already open", null)
                        return@setMethodCallHandler
                    }
                    val filename = call.argument<String>("filename") ?: "tenx_export.txt"
                    val mimeType = call.argument<String>("mimeType") ?: "text/plain"
                    val content = call.argument<String>("content")
                    if (content == null) {
                        result.error("EXPORT_INVALID", "Export content is missing", null)
                        return@setMethodCallHandler
                    }
                    pendingExportResult = result
                    pendingExportContent = content
                    try {
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = mimeType
                            putExtra(Intent.EXTRA_TITLE, filename)
                        }
                        startActivityForResult(intent, REQUEST_CODE_SAVE_EXPORT)
                    } catch (e: Exception) {
                        pendingExportResult = null
                        pendingExportContent = null
                        result.error("EXPORT_PICKER_FAILED", e.localizedMessage, null)
                    }
                }
                "getRingtones" -> {
                    try {
                        val ringtones = getAvailableRingtones()
                        result.success(ringtones)
                    } catch (e: Exception) {
                        result.error("RINGTONE_ERROR", e.localizedMessage, null)
                    }
                }
                "playAlarm" -> {
                    val uriString = call.argument<String>("uri")
                    val looping = call.argument<Boolean>("looping") ?: true
                    val volume = call.argument<Double>("volume") ?: 0.85
                    val forceMaxVolume = call.argument<Boolean>("forceMaxVolume") ?: false
                    val volumeEscalation = call.argument<Boolean>("volumeEscalation") ?: true
                    val vibrationMode = call.argument<String>("vibrationMode") ?: "Continuous"
                    val audioDucking = call.argument<Boolean>("audioDucking") ?: true
                    val flashlightStrobe = call.argument<Boolean>("flashlightStrobe") ?: false
                    val headphoneSafety = call.argument<Boolean>("headphoneSafety") ?: true
                    val screenWakeup = call.argument<Boolean>("screenWakeup") ?: true
                    val ttsText = call.argument<String>("ttsText")
                    val ttsRate = call.argument<String>("ttsRate") ?: "1.0x"
                    try {
                        AlarmPlayer.playAlarm(
                            this,
                            uriString,
                            looping,
                            volume,
                            forceMaxVolume,
                            volumeEscalation,
                            vibrationMode,
                            audioDucking,
                            flashlightStrobe,
                            headphoneSafety,
                            screenWakeup,
                            ttsText,
                            ttsRate
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("PLAY_ERROR", e.localizedMessage, null)
                    }
                }
                "stopAlarm" -> {
                    AlarmPlayer.stopAlarm(this)
                    startService(Intent(this, AlertForegroundService::class.java).apply {
                        action = AlertForegroundService.ACTION_DISMISS_ALARM
                    })
                    result.success(true)
                }
                "setAlertWindowMode" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val wakeScreen = call.argument<Boolean>("wakeScreen") ?: true
                    alertWindowMode = enabled
                    if (enabled) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) setTurnScreenOn(wakeScreen)
                        if (wakeScreen) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        applyAlertImmersiveMode()
                    } else {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) setTurnScreenOn(false)
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        window.decorView.systemUiVisibility = android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            window.insetsController?.show(WindowInsets.Type.systemBars())
                        }
                    }
                    result.success(true)
                }
                "playShortBeep" -> {
                    try {
                        val tone = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 65)
                        tone.startTone(ToneGenerator.TONE_PROP_BEEP, 280)
                        Handler(Looper.getMainLooper()).postDelayed({ tone.release() }, 400)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("BEEP_ERROR", e.localizedMessage, null)
                    }
                }
                "setLowBatteryWarning" -> {
                    val level = call.argument<Int>("level")
                    try {
                        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        if (level == null) {
                            manager.cancel(AlertForegroundService.LOW_BATTERY_NOTIFICATION_ID)
                        } else {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                manager.createNotificationChannel(
                                    NotificationChannel(
                                        AlertForegroundService.LOW_BATTERY_CHANNEL_ID,
                                        "Low Battery Protection",
                                        NotificationManager.IMPORTANCE_DEFAULT
                                    ).apply {
                                        description = "A quiet warning when market monitoring enters battery protection"
                                        setSound(null, null)
                                        enableVibration(false)
                                        setShowBadge(false)
                                    }
                                )
                            }
                            val launchIntent = Intent(this, MainActivity::class.java).apply {
                                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                            }
                            val pendingIntent = android.app.PendingIntent.getActivity(
                                this,
                                AlertForegroundService.LOW_BATTERY_NOTIFICATION_ID,
                                launchIntent,
                                android.app.PendingIntent.FLAG_IMMUTABLE or
                                    android.app.PendingIntent.FLAG_UPDATE_CURRENT
                            )
                            val notification = NotificationCompat.Builder(
                                this,
                                AlertForegroundService.LOW_BATTERY_CHANNEL_ID
                            )
                                .setSmallIcon(android.R.drawable.ic_lock_idle_low_battery)
                                .setContentTitle("TenX battery protection active")
                                .setContentText("Battery is at $level%. Market checks are reduced to conserve power.")
                                .setContentIntent(pendingIntent)
                                .setAutoCancel(true)
                                .setOnlyAlertOnce(true)
                                .build()
                            manager.notify(AlertForegroundService.LOW_BATTERY_NOTIFICATION_ID, notification)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "previewRingtone" -> {
                    val uriString = call.argument<String>("uri")
                    try {
                        previewRingtone(uriString)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("PREVIEW_ERROR", e.localizedMessage, null)
                    }
                }
                "stopPreview" -> {
                    stopPreview()
                    result.success(true)
                }
                "syncActiveAlerts" -> {
                    try {
                        val alertsJson = call.argument<String>("alerts") ?: "[]"
                        val prefs = getSharedPreferences(AlertForegroundService.PREFS_NAME, Context.MODE_PRIVATE)
                        // Commit before starting the foreground monitor. The
                        // monitor may evaluate immediately while this app task
                        // is being removed, so apply() is too late here.
                        if (!prefs.edit()
                                .putString(AlertForegroundService.KEY_ACTIVE_ALERTS, alertsJson)
                                .commit()) {
                            throw IllegalStateException("Could not persist active alerts")
                        }
                        AlertDeadlineScheduler.schedule(this, alertsJson)

                        val monitoringEnabled = prefs.getString(
                            "setting_perpetual_service",
                            prefs.getString("flutter.setting_perpetual_service", "true")
                        ) != "false"
                        if (monitoringEnabled) {
                            // If Android has stopped the service, sync must restart it
                            // as a foreground service so monitoring survives app close.
                            val intent = Intent(this, AlertForegroundService::class.java).apply {
                                action = AlertForegroundService.ACTION_SYNC_ALERTS
                                putExtra(AlertForegroundService.EXTRA_ALERTS_JSON, alertsJson)
                            }
                            ContextCompat.startForegroundService(this, intent)
                            AlarmWatchdog.scheduleNextWatchdog(this, 15000L)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SYNC_ERROR", e.localizedMessage, null)
                    }
                }
                "saveStorage" -> {
                    try {
                        val key = call.argument<String>("key") ?: ""
                        val value = call.argument<String>("value") ?: ""
                        val prefs = getSharedPreferences(AlertForegroundService.PREFS_NAME, Context.MODE_PRIVATE)
                        prefs.edit().putString(key, value).apply()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("STORAGE_ERROR", e.localizedMessage, null)
                    }
                }
                "loadStorage" -> {
                    try {
                        val key = call.argument<String>("key") ?: ""
                        val prefs = getSharedPreferences(AlertForegroundService.PREFS_NAME, Context.MODE_PRIVATE)
                        val value = prefs.getString(key, null)
                        result.success(value)
                    } catch (e: Exception) {
                        result.error("STORAGE_ERROR", e.localizedMessage, null)
                    }
                }
                "listStorageKeysWithPrefix" -> {
                    try {
                        val prefix = call.argument<String>("prefix") ?: ""
                        val prefs = getSharedPreferences(AlertForegroundService.PREFS_NAME, Context.MODE_PRIVATE)
                        result.success(prefs.all.keys.filter { it.startsWith(prefix) }.sorted())
                    } catch (e: Exception) {
                        result.error("STORAGE_ENUMERATION_ERROR", e.localizedMessage, null)
                    }
                }
                "removeStorage" -> {
                    try {
                        val key = call.argument<String>("key") ?: ""
                        val prefs = getSharedPreferences(AlertForegroundService.PREFS_NAME, Context.MODE_PRIVATE)
                        prefs.edit().remove(key).apply()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("STORAGE_ERROR", e.localizedMessage, null)
                    }
                }
                "startForegroundService" -> {
                    try {
                        val intent = Intent(this, AlertForegroundService::class.java).apply {
                            action = AlertForegroundService.ACTION_START
                        }
                        ContextCompat.startForegroundService(this, intent)
                        AlarmWatchdog.scheduleNextWatchdog(this, 15000L)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.localizedMessage, null)
                    }
                }
                "stopForegroundService" -> {
                    try {
                        AlarmWatchdog.cancelWatchdog(this)
                        val intent = Intent(this, AlertForegroundService::class.java).apply {
                            action = AlertForegroundService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.localizedMessage, null)
                    }
                }
                "isDndOverrideGranted" -> {
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    result.success(nm.isNotificationPolicyAccessGranted)
                }
                "requestDndOverride" -> {
                    try {
                        val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("DND_SETTINGS_ERROR", e.localizedMessage, null)
                    }
                }
                "isBatteryOptimizationIgnored" -> {
                    try {
                        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            result.success(powerManager.isIgnoringBatteryOptimizations(packageName))
                        } else {
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "requestIgnoreBatteryOptimizations" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        // Fallback to battery optimization settings list
                        try {
                            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                            startActivity(intent)
                            result.success(true)
                        } catch (e2: Exception) {
                            result.error("BATTERY_SETTINGS_ERROR", e2.localizedMessage, null)
                        }
                    }
                }
                "canDrawOverlays" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            result.success(Settings.canDrawOverlays(this))
                        } else {
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "isFullScreenIntentAllowed" -> {
                    try {
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        result.success(Build.VERSION.SDK_INT < 34 || nm.canUseFullScreenIntent())
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "areNotificationsEnabled" -> {
                    result.success(androidx.core.app.NotificationManagerCompat.from(this).areNotificationsEnabled())
                }
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(this, android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                        requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 9030)
                    }
                    result.success(true)
                }
                "isFlashlightAvailable" -> {
                    result.success(packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_CAMERA_FLASH))
                }
                "requestCameraPermission" -> {
                    if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                        result.success(true)
                    } else {
                        pendingCameraPermissionResult = result
                        requestPermissions(arrayOf(android.Manifest.permission.CAMERA), 9031)
                    }
                }
                "requestFullScreenIntentPermission" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= 34) {
                            startActivity(Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                                data = Uri.parse("package:$packageName")
                            })
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("FULL_SCREEN_SETTINGS_ERROR", e.localizedMessage, null)
                    }
                }
                "requestOverlayPermission" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OVERLAY_SETTINGS_ERROR", e.localizedMessage, null)
                    }
                }
                "pickCustomAudio" -> {
                    pendingPickAudioResult = result
                    try {
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "audio/*"
                            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("audio/mpeg", "audio/wav", "audio/ogg", "audio/mp4", "audio/x-m4a", "audio/aac"))
                        }
                        startActivityForResult(intent, REQUEST_CODE_PICK_AUDIO)
                    } catch (e: Exception) {
                        pendingPickAudioResult = null
                        result.error("PICK_ERROR", e.localizedMessage, null)
                    }
                }
                "getCustomAudios" -> {
                    try {
                        val list = getStoredCustomAudios()
                        result.success(list)
                    } catch (e: Exception) {
                        result.error("CUSTOM_AUDIO_ERROR", e.localizedMessage, null)
                    }
                }
                "deleteCustomAudio" -> {
                    try {
                        val path = call.argument<String>("path") ?: ""
                        val success = deleteStoredCustomAudio(path)
                        result.success(success)
                    } catch (e: Exception) {
                        result.error("DELETE_AUDIO_ERROR", e.localizedMessage, null)
                    }
                }
                "getSystemTelemetry" -> {
                    try {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        val isDnd = nm.isNotificationPolicyAccessGranted
                        val isBattery = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) pm.isIgnoringBatteryOptimizations(packageName) else true
                        val isOverlay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) Settings.canDrawOverlays(this) else true
                        val pid = android.os.Process.myPid()
                        val monitorPrefs = getSharedPreferences(AlertForegroundService.PREFS_NAME, Context.MODE_PRIVATE)
                        val lastMonitorCheck = monitorPrefs.getLong(AlertForegroundService.KEY_MONITOR_LAST_CHECK, 0L)
                        val isRunning = monitorPrefs.getBoolean(AlertForegroundService.KEY_MONITOR_RUNNING, false) &&
                            System.currentTimeMillis() - lastMonitorCheck < 60000L
                        val runtime = Runtime.getRuntime()
                        val usedMemMb = (runtime.totalMemory() - runtime.freeMemory()) / (1024 * 1024)
                        val maxMemMb = runtime.maxMemory() / (1024 * 1024)
                        val abi = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                            Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a"
                        } else {
                            Build.CPU_ABI ?: "arm64-v8a"
                        }
                        val bm = getSystemService(Context.BATTERY_SERVICE) as? android.os.BatteryManager
                        val batteryLevel = bm?.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
                        result.success(mapOf(
                            "os" to "Android ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})",
                            "abi" to abi,
                            "model" to "${Build.MANUFACTURER} ${Build.MODEL}",
                            "pid" to pid,
                            "daemonRunning" to isRunning,
                            "dndGranted" to isDnd,
                            "batteryIgnored" to isBattery,
                            "batteryLevel" to batteryLevel,
                            "overlayGranted" to isOverlay,
                            "memoryUsedMb" to usedMemMb,
                            "memoryMaxMb" to maxMemMb
                        ))
                    } catch (e: Exception) {
                        result.error("TELEMETRY_ERROR", e.localizedMessage, null)
                    }
                }
                "authenticateBiometrics" -> {
                    try {
                        val km = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                        if (km == null || !km.isDeviceSecure) {
                            // Never enable app lock without a credential the OS can verify.
                            result.success(false)
                        } else {
                            pendingAuthResult = result
                            val authIntent = km.createConfirmDeviceCredentialIntent(
                                "TenX Security Shield",
                                "Confirm your fingerprint, face, or device PIN to continue"
                            )
                            if (authIntent != null) {
                                startActivityForResult(authIntent, REQUEST_CODE_AUTH)
                            } else {
                                pendingAuthResult = null
                                result.success(false)
                            }
                        }
                    } catch (e: Exception) {
                        pendingAuthResult = null
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_SAVE_EXPORT) {
            val result = pendingExportResult
            val content = pendingExportContent
            pendingExportResult = null
            pendingExportContent = null
            if (resultCode != RESULT_OK || data?.data == null) {
                result?.success(false)
            } else {
                try {
                    contentResolver.openOutputStream(data.data!!, "wt")!!.bufferedWriter(Charsets.UTF_8).use { it.write(content ?: "") }
                    result?.success(true)
                } catch (e: Exception) {
                    result?.error("EXPORT_WRITE_FAILED", e.localizedMessage, null)
                }
            }
        } else if (requestCode == REQUEST_CODE_AUTH) {
            val success = (resultCode == RESULT_OK)
            pendingAuthResult?.success(success)
            pendingAuthResult = null
        } else if (requestCode == REQUEST_CODE_PICK_AUDIO) {
            if (resultCode == RESULT_OK && data?.data != null) {
                try {
                    val item = saveAudioUriToInternal(data.data!!)
                    pendingPickAudioResult?.success(item)
                } catch (e: Exception) {
                    pendingPickAudioResult?.error("SAVE_ERROR", e.localizedMessage, null)
                }
            } else {
                pendingPickAudioResult?.success(null)
            }
            pendingPickAudioResult = null
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 9031) {
            val granted = grantResults.firstOrNull() == android.content.pm.PackageManager.PERMISSION_GRANTED
            pendingCameraPermissionResult?.success(granted)
            pendingCameraPermissionResult = null
        }
    }

    private fun saveAudioUriToInternal(uri: Uri): Map<String, String>? {
        val dir = File(filesDir, "custom_audio")
        if (!dir.exists()) dir.mkdirs()

        var displayName = "custom_tone_${System.currentTimeMillis()}"
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
            if (nameIndex != -1 && cursor.moveToFirst()) {
                val found = cursor.getString(nameIndex)
                if (!found.isNullOrBlank()) displayName = found
            }
        }

        val destFile = File(dir, displayName)
        contentResolver.openInputStream(uri)?.use { input ->
            destFile.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        return mapOf(
            "title" to destFile.nameWithoutExtension,
            "uri" to destFile.absolutePath,
            "type" to "custom"
        )
    }

    private fun getStoredCustomAudios(): List<Map<String, String>> {
        val list = mutableListOf<Map<String, String>>()
        val dir = File(filesDir, "custom_audio")
        if (dir.exists() && dir.isDirectory) {
            dir.listFiles()?.forEach { file ->
                if (file.isFile && file.length() > 0) {
                    list.add(mapOf(
                        "title" to file.nameWithoutExtension,
                        "uri" to file.absolutePath,
                        "type" to "custom"
                    ))
                }
            }
        }
        return list
    }

    private fun deleteStoredCustomAudio(path: String): Boolean {
        try {
            val file = File(path)
            if (file.exists() && file.parentFile?.name == "custom_audio") {
                return file.delete()
            }
        } catch (_: Exception) {}
        return false
    }

    private fun configureLockScreenDisplay() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val km = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            km?.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        configureLockScreenDisplay()
        if (intent.action == "com.example.alert_app.ALARM_TRIGGER" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            val wake = getSharedPreferences(AlertForegroundService.PREFS_NAME, Context.MODE_PRIVATE)
                .getString("setting_screen_wakeup", "true") == "true"
            setTurnScreenOn(wake)
        }
        handleAlarmIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        isInForeground = true
        configureLockScreenDisplay()
        if (alertWindowMode) applyAlertImmersiveMode()
        handleAlarmIntent(intent)
    }

    @Suppress("DEPRECATION")
    private fun applyAlertImmersiveMode() {
        window.decorView.systemUiVisibility = (
            android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
            android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
            android.view.View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
            android.view.View.SYSTEM_UI_FLAG_FULLSCREEN or
            android.view.View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
            android.view.View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.let { controller ->
                controller.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                controller.systemBarsBehavior =
                    android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        }
    }

    override fun onPause() {
        isInForeground = false
        super.onPause()
    }

    private fun handleAlarmIntent(intent: Intent?) {
        if (intent?.action == "com.example.alert_app.ALARM_TRIGGER") {
            val symbol = intent.getStringExtra("symbol") ?: ""
            val triggerPrice = intent.getDoubleExtra("triggerPrice", 0.0)
            if (symbol.isNotEmpty()) {
                val alarm = mapOf<String, Any>(
                    "symbol" to symbol,
                    "triggerPrice" to triggerPrice
                )
                pendingAlarm = alarm
                mainMethodChannel?.invokeMethod("onAlarmTriggered", alarm, object : MethodChannel.Result {
                    override fun success(result: Any?) { pendingAlarm = null }
                    override fun error(code: String, message: String?, details: Any?) { }
                    override fun notImplemented() { }
                })
            }
            intent.action = null
        }
    }

    private fun getAvailableRingtones(): List<Map<String, String>> {
        val list = mutableListOf<Map<String, String>>()
        
        // 1. Add user-uploaded custom sounds first
        list.addAll(getStoredCustomAudios())

        val manager = RingtoneManager(this)

        // 2. Query alarms
        try {
            manager.setType(RingtoneManager.TYPE_ALARM)
            val cursor = manager.cursor
            while (cursor != null && cursor.moveToNext()) {
                val title = cursor.getString(RingtoneManager.TITLE_COLUMN_INDEX)
                val uri = manager.getRingtoneUri(cursor.position)?.toString() ?: ""
                if (uri.isNotEmpty() && list.none { it["uri"] == uri }) {
                    list.add(mapOf("title" to title, "uri" to uri, "type" to "alarm"))
                }
            }
        } catch (_: Exception) {}

        // 3. Also query standard ringtones
        try {
            manager.setType(RingtoneManager.TYPE_RINGTONE)
            val cursor = manager.cursor
            while (cursor != null && cursor.moveToNext()) {
                val title = cursor.getString(RingtoneManager.TITLE_COLUMN_INDEX)
                val uri = manager.getRingtoneUri(cursor.position)?.toString() ?: ""
                if (uri.isNotEmpty() && list.none { it["uri"] == uri }) {
                    list.add(mapOf("title" to title, "uri" to uri, "type" to "ringtone"))
                }
            }
        } catch (_: Exception) {}

        // If list is empty (fallback), add default alarm URI
        if (list.isEmpty()) {
            val defaultUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            if (defaultUri != null) {
                list.add(mapOf("title" to "Default Alarm", "uri" to defaultUri.toString(), "type" to "alarm"))
            }
        }

        return list
    }

    private fun previewRingtone(uriString: String?) {
        stopPreview()
        if (uriString.isNullOrEmpty()) return

        val uri = if (uriString.startsWith("/")) Uri.fromFile(File(uriString)) else Uri.parse(uriString)
        previewPlayer = MediaPlayer().apply {
            setDataSource(applicationContext, uri)
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            isLooping = false
            prepare()
            start()
        }

        // Auto stop after 3 seconds
        previewRunnable = Runnable { stopPreview() }
        previewHandler.postDelayed(previewRunnable!!, 3000)
    }

    private fun stopPreview() {
        previewRunnable?.let { previewHandler.removeCallbacks(it) }
        previewRunnable = null
        try {
            previewPlayer?.let {
                if (it.isPlaying) {
                    it.stop()
                }
                it.release()
            }
        } catch (_: Exception) {}
        previewPlayer = null
    }

    override fun onDestroy() {
        AlarmPlayer.stopAlarm(this)
        stopPreview()
        super.onDestroy()
    }
}
