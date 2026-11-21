package com.example.alert_app

import android.app.NotificationManager
import android.content.Context
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraCharacteristics
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.AudioDeviceInfo
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.speech.tts.TextToSpeech
import java.io.File
import java.util.Locale

object AlarmPlayer {
    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var screenWakeLock: PowerManager.WakeLock? = null
    private var originalAlarmVolume: Int? = null
    private var originalInterruptionFilter: Int? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var escalationRunnable: Runnable? = null
    private var torchRunnable: Runnable? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var audioFocusRequest: Any? = null
    private var isTorchOn = false
    private var torchCameraId: String? = null

    var isPlaying: Boolean = false
        private set

    fun playAlarm(
        context: Context,
        uriString: String?,
        looping: Boolean = true,
        volume: Double = 0.85,
        forceMaxVolume: Boolean = false,
        volumeEscalation: Boolean = true,
        vibrationMode: String = "Continuous",
        audioDucking: Boolean = true,
        flashlightStrobe: Boolean = false,
        headphoneSafety: Boolean = true,
        screenWakeup: Boolean = true,
        ttsText: String? = null,
        ttsRate: String = "1.0x"
    ) {
        stopAlarm(context)
        isPlaying = true

        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

        // 1. Wake up the screen immediately
        if (screenWakeup) wakeUpScreen(context)

        // 2. Override DND if permission is granted
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.isNotificationPolicyAccessGranted) {
            try {
                if (originalInterruptionFilter == null) {
                    originalInterruptionFilter = nm.currentInterruptionFilter
                }
                nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL)
            } catch (_: Exception) {}
        }

        // 3. Audio Ducking
        if (audioDucking) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val focusReq = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                        .setAudioAttributes(
                            AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_ALARM)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                .build()
                        )
                        .build()
                    audioFocusRequest = focusReq
                    audioManager.requestAudioFocus(focusReq)
                } else {
                    @Suppress("DEPRECATION")
                    audioManager.requestAudioFocus(null, AudioManager.STREAM_ALARM, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                }
            } catch (_: Exception) {}
        }

        // 4. Volume Resolution & Headphone Safety
        if (originalAlarmVolume == null) {
            originalAlarmVolume = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
        }
        val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
        var effVol = if (forceMaxVolume) 1.0 else volume.coerceIn(0.0, 1.0)

        // Headphone safety limiter: cap at 70% if headphones connected
        if (headphoneSafety && isHeadsetConnected(audioManager)) {
            effVol = effVol.coerceAtMost(0.70)
        }

        val targetVol = (maxVol * effVol).toInt().coerceAtLeast(1)

        if (volumeEscalation && targetVol > 1) {
            // Start at 30% and reach the selected target in five elapsed seconds.
            val startVol = (maxVol * 0.30).toInt().coerceAtLeast(1).coerceAtMost(targetVol)
            try {
                audioManager.setStreamVolume(AudioManager.STREAM_ALARM, startVol, 0)
            } catch (_: Exception) {}

            val rampStartedAt = SystemClock.elapsedRealtime()
            escalationRunnable = object : Runnable {
                override fun run() {
                    if (!isPlaying) return
                    val elapsed = (SystemClock.elapsedRealtime() - rampStartedAt).coerceAtLeast(0L)
                    val progress = (elapsed / 5_000.0).coerceIn(0.0, 1.0)
                    val currentVolume = (startVol + (targetVol - startVol) * progress)
                        .toInt().coerceIn(startVol, targetVol)
                    try {
                        audioManager.setStreamVolume(AudioManager.STREAM_ALARM, currentVolume, 0)
                    } catch (_: Exception) {}
                    if (progress < 1.0) mainHandler.postDelayed(this, 100L)
                }
            }
            mainHandler.postDelayed(escalationRunnable!!, 100L)
        } else {
            try {
                audioManager.setStreamVolume(AudioManager.STREAM_ALARM, targetVol, 0)
            } catch (_: Exception) {}
        }

        // 5. Text-To-Speech announcement if specified
        if (!ttsText.isNullOrBlank()) {
            speakTts(context.applicationContext, ttsText, ttsRate)
        }

        // 6. Play alarm audio using MediaPlayer with USAGE_ALARM
        val uri = if (!uriString.isNullOrEmpty()) {
            if (uriString.startsWith("/")) Uri.fromFile(File(uriString)) else Uri.parse(uriString)
        } else {
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        }

        try {
            mediaPlayer = MediaPlayer().apply {
                setDataSource(context.applicationContext, uri)
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                isLooping = looping
                prepare()
                start()
            }
        } catch (_: Exception) {
            // A custom sound can be removed while an existing alert still
            // references it. Keep the alert audible with the system alarm tone.
            val fallbackUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            if (fallbackUri != null && fallbackUri != uri) {
                try {
                    mediaPlayer?.release()
                    mediaPlayer = MediaPlayer().apply {
                        setDataSource(context.applicationContext, fallbackUri)
                        setAudioAttributes(
                            AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_ALARM)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                .build()
                        )
                        isLooping = looping
                        prepare()
                        start()
                    }
                } catch (_: Exception) {
                    mediaPlayer?.release()
                    mediaPlayer = null
                }
            }
        }

        // 7. Configurable Vibration Pattern
        if (!vibrationMode.equals("None", ignoreCase = true)) {
            val timings = when (vibrationMode.lowercase()) {
                "heartbeat" -> longArrayOf(0, 150, 150, 150, 600)
                "sos strobe", "sos" -> longArrayOf(0, 150, 100, 150, 100, 150, 300, 400, 150, 400, 150, 400, 300, 150, 100, 150, 100, 150, 800)
                else -> longArrayOf(0, 600, 200, 600) // Continuous
            }
            try {
                vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val amplitudes = IntArray(timings.size) { i -> if (i % 2 == 1) 255 else 0 }
                    vibrator?.vibrate(VibrationEffect.createWaveform(timings, amplitudes, 0))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator?.vibrate(timings, 0)
                }
            } catch (_: Exception) {}
        }

        // 8. Flashlight Strobe Alert
        if (flashlightStrobe) {
            startFlashlightStrobe(context)
        }
    }

    private fun isHeadsetConnected(audioManager: AudioManager): Boolean {
        return try {
            audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { device ->
                when (device.type) {
                    AudioDeviceInfo.TYPE_WIRED_HEADSET,
                    AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                    AudioDeviceInfo.TYPE_USB_HEADSET,
                    AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                    AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> true
                    else -> Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                        device.type in setOf(
                            AudioDeviceInfo.TYPE_BLE_HEADSET,
                            AudioDeviceInfo.TYPE_BLE_SPEAKER
                        )
                }
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun speakTts(appContext: Context, text: String, rateStr: String) {
        val rate = rateStr.replace("x", "").toFloatOrNull() ?: 1.0f
        tts = TextToSpeech(appContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                tts?.language = Locale.US
                tts?.setSpeechRate(rate)
                tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "AlarmTtsId")
            }
        }
    }

    private fun startFlashlightStrobe(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager ?: return
            val cameraId = cameraManager.cameraIdList.firstOrNull { id ->
                cameraManager.getCameraCharacteristics(id)
                    .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            } ?: return
            torchCameraId = cameraId
            
            torchRunnable = object : Runnable {
                override fun run() {
                    if (!isPlaying) {
                        try { cameraManager.setTorchMode(cameraId, false) } catch (_: Exception) {}
                        return
                    }
                    try {
                        isTorchOn = !isTorchOn
                        cameraManager.setTorchMode(cameraId, isTorchOn)
                    } catch (_: Exception) {}
                    mainHandler.postDelayed(this, 250)
                }
            }
            mainHandler.post(torchRunnable!!)
        } catch (_: Exception) {}
    }

    private fun stopFlashlightStrobe(context: Context) {
        torchRunnable?.let { mainHandler.removeCallbacks(it) }
        torchRunnable = null
        if (isTorchOn && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
                val cameraId = torchCameraId
                if (cameraId != null) {
                    cameraManager?.setTorchMode(cameraId, false)
                }
            } catch (_: Exception) {}
            isTorchOn = false
            torchCameraId = null
        }
    }

    private fun wakeUpScreen(context: Context) {
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        screenWakeLock = powerManager.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "AlertApp:AlarmScreenWakeLock"
        ).apply {
            acquire(30000) // Keep screen on for up to 30 seconds
        }
    }

    fun stopAlarm(context: Context) {
        isPlaying = false

        // Cancel volume ramp
        escalationRunnable?.let { mainHandler.removeCallbacks(it) }
        escalationRunnable = null

        // Stop Flashlight Strobe
        stopFlashlightStrobe(context)

        // Stop TTS
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {}
        tts = null

        // Stop media playback
        try {
            mediaPlayer?.let {
                if (it.isPlaying) {
                    it.stop()
                }
                it.release()
            }
        } catch (_: Exception) {}
        mediaPlayer = null

        // Stop vibration
        try {
            vibrator?.cancel()
        } catch (_: Exception) {}
        vibrator = null

        // Restore original system alarm volume
        originalAlarmVolume?.let { orig ->
            try {
                val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                audioManager.setStreamVolume(AudioManager.STREAM_ALARM, orig, 0)
            } catch (_: Exception) {}
            originalAlarmVolume = null
        }

        // Abandon audio focus
        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && audioFocusRequest is AudioFocusRequest) {
                audioManager.abandonAudioFocusRequest(audioFocusRequest as AudioFocusRequest)
            } else {
                @Suppress("DEPRECATION")
                audioManager.abandonAudioFocus(null)
            }
        } catch (_: Exception) {}
        audioFocusRequest = null

        // Restore the user's prior Do Not Disturb mode after the alarm ends.
        originalInterruptionFilter?.let { filter ->
            try {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                if (nm.isNotificationPolicyAccessGranted) nm.setInterruptionFilter(filter)
            } catch (_: Exception) {}
            originalInterruptionFilter = null
        }

        // Release wake lock
        try {
            screenWakeLock?.let {
                if (it.isHeld) it.release()
            }
        } catch (_: Exception) {}
        screenWakeLock = null
    }
}
