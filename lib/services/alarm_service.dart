import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'settings_provider.dart';

class RingtoneItem {
  final String title;
  final String uri;
  final String type; // 'alarm' or 'ringtone'

  const RingtoneItem({
    required this.title,
    required this.uri,
    this.type = 'alarm',
  });

  factory RingtoneItem.fromMap(Map<dynamic, dynamic> map) {
    return RingtoneItem(
      title: map['title']?.toString() ?? 'Unknown Tone',
      uri: map['uri']?.toString() ?? '',
      type: map['type']?.toString() ?? 'alarm',
    );
  }
}

class AlarmService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.alert_app/alarm',
  );
  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  /// Fetch all system alarm sounds and ringtones
  Future<List<RingtoneItem>> getRingtones() async {
    try {
      final List<dynamic>? list = await _channel.invokeMethod<List<dynamic>>(
        'getRingtones',
      );
      return (list ?? const [])
          .whereType<Map>()
          .map((item) => RingtoneItem.fromMap(item))
          .toList();
    } catch (_) {
      // Native ringtone enumeration is unavailable on unsupported platforms.
      return [];
    }
  }

  /// Launch system audio picker to upload user audio file (.mp3, .wav, .m4a, .ogg)
  Future<RingtoneItem?> pickCustomAudio() async {
    try {
      final Map<dynamic, dynamic>? res = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('pickCustomAudio');
      if (res != null) {
        return RingtoneItem.fromMap(res);
      }
    } catch (_) {}
    return null;
  }

  /// Fetch all user-uploaded custom audio files
  Future<List<RingtoneItem>> getCustomAudios() async {
    try {
      final List<dynamic>? list = await _channel.invokeMethod<List<dynamic>>(
        'getCustomAudios',
      );
      if (list != null) {
        return list
            .whereType<Map>()
            .map((m) => RingtoneItem.fromMap(m))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Delete a user-uploaded custom audio file by absolute path
  Future<bool> deleteCustomAudio(String path) async {
    try {
      final bool? res = await _channel.invokeMethod<bool>('deleteCustomAudio', {
        'path': path,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Timer? _autoSilenceTimer;

  /// Start playing the alarm continuously with screen wakeup, custom vibration, ducking, strobe & TTS
  Future<void> playAlarm({
    String? ringtoneUri,
    bool looping = true,
    double? volume,
    bool? forceMaxVolume,
    bool? volumeEscalation,
    String? vibrationMode,
    int? autoSilenceSeconds,
    bool? audioDucking,
    bool? flashlightStrobe,
    bool? headphoneSafety,
    bool? screenWakeup,
    bool? ttsEnabled,
    String? ttsText,
    String? ttsRate,
    bool isCritical = false,
  }) async {
    _autoSilenceTimer?.cancel();
    _isPlaying = true;

    final settings = SettingsProvider();
    final effectiveUri = (ringtoneUri != null && ringtoneUri.isNotEmpty)
        ? ringtoneUri
        : settings.soundUri;
    final effectiveVolume =
        volume ?? settings.resolveEffectiveVolume(isCritical: isCritical);
    final effectiveForceMax = forceMaxVolume ?? settings.forceMaxVolume;
    final effectiveEscalation = volumeEscalation ?? settings.volumeEscalation;
    final effectiveVibration = vibrationMode ?? settings.vibrationMode;
    final effectiveDucking = audioDucking ?? settings.audioDucking;
    final effectiveStrobe = flashlightStrobe ?? settings.flashlightStrobe;
    final effectiveHeadphoneSafety =
        headphoneSafety ?? settings.headphoneSafety;
    final effectiveTtsEnabled = ttsEnabled ?? settings.ttsEnabled;
    final effectiveTtsText = effectiveTtsEnabled ? ttsText : null;
    final effectiveTtsRate = ttsRate ?? settings.ttsSpeechRate;
    final effectiveAutoSilence =
        autoSilenceSeconds ?? settings.autoSilenceSeconds;
    final effectiveScreenWakeup = screenWakeup ?? settings.screenWakeup;

    try {
      await _channel.invokeMethod('playAlarm', {
        'uri': effectiveUri,
        'looping': looping,
        'volume': effectiveVolume,
        'forceMaxVolume': effectiveForceMax,
        'volumeEscalation': effectiveEscalation,
        'vibrationMode': effectiveVibration,
        'audioDucking': effectiveDucking,
        'flashlightStrobe': effectiveStrobe,
        'headphoneSafety': effectiveHeadphoneSafety,
        'screenWakeup': effectiveScreenWakeup,
        'ttsText': effectiveTtsText,
        'ttsRate': effectiveTtsRate,
      });
    } catch (_) {}

    if (effectiveAutoSilence > 0) {
      _autoSilenceTimer = Timer(Duration(seconds: effectiveAutoSilence), () {
        stopAlarm();
      });
    }
  }

  /// Play a brief, one-shot connection warning without starting the configured
  /// looping price alarm, vibration pattern, escalation, or speech.
  Future<void> playShortBeep() async {
    try {
      await _channel.invokeMethod('playShortBeep');
    } catch (_) {}
  }

  /// Show or clear the low-battery protection notification. A null level
  /// clears the warning after recovery or when the protection setting is off.
  Future<void> setLowBatteryWarning(int? level) async {
    try {
      await _channel.invokeMethod('setLowBatteryWarning', {'level': level});
    } catch (_) {}
  }

  /// Stop playing the alarm
  Future<void> stopAlarm() async {
    _autoSilenceTimer?.cancel();
    _isPlaying = false;
    try {
      await _channel.invokeMethod('stopAlarm');
    } catch (_) {}
  }

  /// Preview a ringtone for 3 seconds
  Future<void> previewRingtone(String uri) async {
    try {
      await _channel.invokeMethod('previewRingtone', {'uri': uri});
    } catch (_) {}
  }

  /// Stop current preview
  Future<void> stopPreview() async {
    try {
      await _channel.invokeMethod('stopPreview');
    } catch (_) {}
  }

  /// Start the perpetual Android Foreground Service
  Future<void> startForegroundService() async {
    try {
      await _channel.invokeMethod('startForegroundService');
    } catch (_) {}
  }

  /// Stop the perpetual Android Foreground Service
  Future<void> stopForegroundService() async {
    try {
      await _channel.invokeMethod('stopForegroundService');
    } catch (_) {}
  }

  /// Check whether Do Not Disturb (DND) override permission is granted
  Future<bool> isDndOverrideGranted() async {
    try {
      final bool? granted = await _channel.invokeMethod<bool>(
        'isDndOverrideGranted',
      );
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Open Android Notification Policy Access Settings to grant DND override
  Future<void> requestDndOverride() async {
    try {
      await _channel.invokeMethod('requestDndOverride');
    } catch (_) {}
  }

  /// Check whether battery optimization is already disabled/ignored for TenX
  Future<bool> isBatteryOptimizationIgnored() async {
    try {
      final bool? isIgnored = await _channel.invokeMethod<bool>(
        'isBatteryOptimizationIgnored',
      );
      return isIgnored ?? true;
    } catch (_) {
      return false;
    }
  }

  /// Request battery optimization exemption so OS doesn't kill monitoring
  Future<void> requestIgnoreBatteryOptimizations() async {
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {}
  }

  /// Check whether system overlay permission (Display over other apps) is granted
  Future<bool> isOverlayPermissionGranted() async {
    try {
      final bool? isGranted = await _channel.invokeMethod<bool>(
        'canDrawOverlays',
      );
      return isGranted ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Open Android settings to grant system overlay permission
  Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } catch (_) {}
  }

  Future<bool> isFullScreenIntentAllowed() async {
    try {
      return await _channel.invokeMethod<bool>('isFullScreenIntentAllowed') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestFullScreenIntentPermission() async {
    try {
      await _channel.invokeMethod('requestFullScreenIntentPermission');
    } catch (_) {}
  }

  Future<bool> areNotificationsEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('areNotificationsEnabled') ??
          false;
    } catch (_) {
      return true;
    }
  }

  Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod('requestNotificationPermission');
    } catch (_) {}
  }

  Future<bool> isFlashlightAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isFlashlightAvailable') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestCameraPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestCameraPermission') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Sync active alerts with Android native background foreground service
  Future<void> syncActiveAlerts(String alertsJson) async {
    try {
      await _channel.invokeMethod('syncActiveAlerts', {'alerts': alertsJson});
    } catch (_) {}
  }

  /// Queries native OS platform telemetry, daemon status, and hardware memory
  Future<Map<String, dynamic>> getSystemTelemetry() async {
    try {
      final Map<dynamic, dynamic>? res = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('getSystemTelemetry');
      if (res != null) {
        return Map<String, dynamic>.from(res);
      }
    } catch (_) {}

    // Report real Dart process details on platforms without the Android bridge.
    final isDnd = await isDndOverrideGranted();
    final isBattery = await isBatteryOptimizationIgnored();
    final isOverlay = await isOverlayPermissionGranted();
    final usedMb = ProcessInfo.currentRss ~/ (1024 * 1024);
    final maxMb = ProcessInfo.maxRss ~/ (1024 * 1024);

    return {
      'os': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'abi': Platform.environment['PROCESSOR_ARCHITECTURE'] ?? 'Unavailable',
      'model': Platform.localHostname,
      'pid': pid,
      'daemonRunning': false,
      'dndGranted': isDnd,
      'batteryIgnored': isBattery,
      'overlayGranted': isOverlay,
      'memoryUsedMb': usedMb,
      'memoryMaxMb': maxMb,
    };
  }

  Future<void> shareText(String text) async {
    await _channel.invokeMethod<bool>('shareText', {'text': text});
  }

  /// Prompts native Android OS device credentials (fingerprint, face, or PIN)
  Future<bool> authenticateBiometrics() async {
    try {
      final bool? success = await _channel.invokeMethod<bool>(
        'authenticateBiometrics',
      );
      return success ?? false;
    } catch (_) {
      return false;
    }
  }
}
