import 'package:flutter/foundation.dart';

import 'storage_service.dart';

class SettingsProvider extends ChangeNotifier {
  static final SettingsProvider _instance = SettingsProvider._internal();
  factory SettingsProvider() => _instance;
  SettingsProvider._internal();

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  // 1. Audio & Sounds
  String _soundTitle = 'System default';
  String _soundUri = 'default_alarm';
  double _alarmVolume = 0.85;
  bool _forceMaxVolume = false;
  bool _volumeEscalation = true;
  bool _quietHoursEnabled = true;
  String _quietHours = '23:00 – 07:00';
  double _quietHoursVolume = 0.25;
  bool _quietHoursBypassCritical = true;
  String _vibrationMode =
      'Continuous'; // 'Continuous', 'Heartbeat', 'SOS Strobe', 'None'
  String _alarmAutoSilence = 'Never'; // 'Never', '30s', '60s'
  bool _ttsEnabled = false;
  String _ttsSpeechRate = '1.0x';
  bool _audioDucking = true;
  bool _flashlightStrobe = false;
  bool _headphoneSafety = true;

  // 2. Background & Permissions
  bool _perpetualServiceActive = true;
  String _pollingRate = 'Standard (5s)';
  bool _screenWakeup = true;
  bool _statusBarTicker = true;
  bool _deadManWarning = true;
  bool _autoNetworkFailover = true;
  bool _lowBatteryGuard = true;

  // 3. AI Deliberation
  double _llmTemperature = 0.20;
  int _llmMaxTokens = 8000;
  String _aiExecutionStrategy = 'Parallel'; // 'Parallel' vs 'Sequential'
  String _aiTraderDirective = '';

  // 4. Market Data
  bool _biquoteAutoReconnect = true;
  bool _directIpFallback = true;
  String _tradingTimezone = 'UTC / GMT';
  bool _transportFallback = true;
  bool _showSpreadDisplay = true;
  // Retained for compatibility with older settings backups and callers. The
  // candle cache no longer applies any retention limit.
  String _offlineCandleRetention = '1,000 bars';
  List<String> _selectedSessions = [
    'London Open (07:00 UTC)',
    'New York Open (12:00 UTC)',
  ];
  String _sessionAlertTiming = 'At Session Open';

  // 5. Trigger & Snooze
  int _defaultSnoozeMinutes = 5;
  String _alertTtl = 'Never';

  // 6. Chart & Terminal
  String _defaultLaunchScreen = 'Market Watch';
  String _defaultChartTimeframe = '15m';
  String _chartCandleType =
      'Japanese Candles'; // 'Japanese Candles', 'Hollow Candles', 'Line Chart'
  bool _showCandleCountdown = true;
  bool _vibrateOnDrag = true;
  bool _magneticSnapping = true;
  bool _sessionShading = true;
  String _colorblindChartMode =
      'Standard'; // 'Standard', 'Deuteranopia', 'Monochrome OLED'

  // 7. Data & System
  bool _biometricAppLock = false;

  // Getters
  String get soundTitle => _soundTitle;
  String get soundUri => _soundUri;
  double get alarmVolume => _alarmVolume;
  bool get forceMaxVolume => _forceMaxVolume;
  bool get volumeEscalation => _volumeEscalation;
  bool get quietHoursEnabled => _quietHoursEnabled;
  String get quietHours => _quietHours;
  double get quietHoursVolume => _quietHoursVolume;
  bool get quietHoursBypassCritical => _quietHoursBypassCritical;
  String get vibrationMode => _vibrationMode;
  String get alarmAutoSilence => _alarmAutoSilence;
  bool get ttsEnabled => _ttsEnabled;
  String get ttsSpeechRate => _ttsSpeechRate;
  bool get audioDucking => _audioDucking;
  bool get flashlightStrobe => _flashlightStrobe;
  bool get headphoneSafety => _headphoneSafety;

  bool get perpetualServiceActive => _perpetualServiceActive;
  String get pollingRate => _pollingRate;
  bool get screenWakeup => _screenWakeup;
  bool get statusBarTicker => _statusBarTicker;
  bool get deadManWarning => _deadManWarning;
  bool get autoNetworkFailover => _autoNetworkFailover;
  bool get lowBatteryGuard => _lowBatteryGuard;

  double get llmTemperature => _llmTemperature;
  int get llmMaxTokens => _llmMaxTokens;
  String get aiExecutionStrategy => _aiExecutionStrategy;
  String get aiTraderDirective => _aiTraderDirective;

  bool get biquoteAutoReconnect => _biquoteAutoReconnect;
  bool get directIpFallback => _directIpFallback;
  String get tradingTimezone => _tradingTimezone;
  bool get transportFallback => _transportFallback;
  bool get showSpreadDisplay => _showSpreadDisplay;
  List<String> get selectedSessions => List.unmodifiable(_selectedSessions);
  String get sessionAlertTiming => _sessionAlertTiming;

  int get defaultSnoozeMinutes => _defaultSnoozeMinutes;
  String get alertTtl => _alertTtl;

  String get defaultLaunchScreen => _defaultLaunchScreen;
  String get defaultChartTimeframe => _defaultChartTimeframe;
  String get chartCandleType => _chartCandleType;
  bool get showCandleCountdown => _showCandleCountdown;
  bool get vibrateOnDrag => _vibrateOnDrag;
  bool get magneticSnapping => _magneticSnapping;
  bool get sessionShading => _sessionShading;
  String get colorblindChartMode => _colorblindChartMode;
  String get offlineCandleRetention => _offlineCandleRetention;

  /// Legacy compatibility value only. The candle cache ignores this value.
  int get candleRetentionCount {
    if (_offlineCandleRetention.contains('500')) return 500;
    if (_offlineCandleRetention.contains('2,000')) return 2000;
    return 1000;
  }

  bool get biometricAppLock => _biometricAppLock;

  // Derived helpers
  Duration get pollingDuration {
    if (_pollingRate.contains('2s')) return const Duration(seconds: 2);
    if (_pollingRate.contains('15s')) return const Duration(seconds: 15);
    return const Duration(seconds: 5);
  }

  Duration? get ttlDuration {
    final lower = _alertTtl.toLowerCase();
    if (lower.contains('24') || lower.contains('hour')) {
      return const Duration(hours: 24);
    }
    if (lower.contains('3') || lower.contains('day')) {
      return const Duration(days: 3);
    }
    if (lower.contains('1') || lower.contains('week')) {
      return const Duration(days: 7);
    }
    return null; // Never
  }

  int get autoSilenceSeconds {
    final lower = _alarmAutoSilence.toLowerCase();
    if (lower.contains('30')) return 30;
    if (lower.contains('60')) return 60;
    return 0; // 0 = ring until dismissed
  }

  /// Calculates whether the provided timestamp is within the configured Quiet Hours window
  bool isNowInQuietHours([DateTime? time]) {
    if (!_quietHoursEnabled) return false;
    final now = time ?? DateTime.now();
    try {
      // Parse the times around any separator so legacy labels remain valid.
      final schedule = RegExp(r'(\d{1,2}:\d{2})[^\d]+(\d{1,2}:\d{2})')
          .firstMatch(_quietHours);
      if (schedule == null) return false;
      final startParts = schedule.group(1)!.split(':');
      final endParts = schedule.group(2)!.split(':');
      final startHour = int.parse(startParts[0]);
      final startMin = int.parse(startParts[1]);
      final endHour = int.parse(endParts[0]);
      final endMin = int.parse(endParts[1]);
      if (startHour > 23 || endHour > 23 || startMin > 59 || endMin > 59) {
        return false;
      }

      final currentMinutes = now.hour * 60 + now.minute;
      final startMinutes = startHour * 60 + startMin;
      final endMinutes = endHour * 60 + endMin;

      if (startMinutes <= endMinutes) {
        return currentMinutes >= startMinutes && currentMinutes < endMinutes;
      } else {
        // Crosses midnight, e.g. 23:00 to 07:00
        return currentMinutes >= startMinutes || currentMinutes < endMinutes;
      }
    } catch (_) {
      return false;
    }
  }

  /// Resolves the actual volume for an alert taking quiet hours and force max volume into account
  double resolveEffectiveVolume({bool isCritical = false, DateTime? time}) {
    if (_forceMaxVolume) return 1.0;
    if (_quietHoursEnabled && isNowInQuietHours(time)) {
      if (isCritical && _quietHoursBypassCritical) {
        return _alarmVolume;
      }
      return _quietHoursVolume;
    }
    return _alarmVolume;
  }

  /// Loads all settings from persistent storage
  Future<void> loadAll() async {
    // Remove retired controls and counters. Keep legacy provider credentials
    // on-device so an app upgrade never destroys user-saved keys. Current API
    // services use build-time configuration, so these values remain unused.
    await Future.wait([
      StorageService.remove('setting_llm_reasoning'),
      StorageService.remove('setting_auto_deliberate_calendar'),
      StorageService.remove('setting_token_usage_prompt'),
      StorageService.remove('setting_token_usage_completion'),
      StorageService.remove('setting_token_usage_cost'),
    ]);
    // 1. Audio
    _soundTitle =
        await StorageService.getString('setting_global_sound_title') ??
        'System default';
    _soundUri =
        await StorageService.getString('setting_global_sound_uri') ??
        'default_alarm';
    _alarmVolume = await StorageService.getDouble(
      'setting_alarm_volume',
      defaultValue: 0.85,
    );
    _forceMaxVolume = await StorageService.getBool(
      'setting_force_max_vol',
      defaultValue: false,
    );
    _volumeEscalation = await StorageService.getBool(
      'setting_volume_escalation',
      defaultValue: true,
    );
    _quietHoursEnabled = await StorageService.getBool(
      'setting_quiet_hours_enabled',
      defaultValue: true,
    );
    _quietHours =
        await StorageService.getString('setting_quiet_hours') ??
        '23:00 – 07:00';
    _quietHoursVolume = await StorageService.getDouble(
      'setting_quiet_hours_vol',
      defaultValue: 0.25,
    );
    _quietHoursBypassCritical = await StorageService.getBool(
      'setting_quiet_bypass',
      defaultValue: true,
    );
    _vibrationMode =
        await StorageService.getString('setting_vibration_mode') ??
        'Continuous';
    _alarmAutoSilence =
        await StorageService.getString('setting_auto_silence') ?? 'Never';
    _ttsEnabled = await StorageService.getBool(
      'setting_tts_enabled',
      defaultValue: false,
    );
    _ttsSpeechRate =
        await StorageService.getString('setting_tts_rate') ?? '1.0x';
    _audioDucking = await StorageService.getBool(
      'setting_audio_ducking',
      defaultValue: true,
    );
    _flashlightStrobe = await StorageService.getBool(
      'setting_flashlight_strobe',
      defaultValue: false,
    );
    _headphoneSafety = await StorageService.getBool(
      'setting_headphone_safety',
      defaultValue: true,
    );

    // 2. Background
    _perpetualServiceActive = await StorageService.getBool(
      'setting_perpetual_service',
      defaultValue: true,
    );
    _pollingRate =
        await StorageService.getString('setting_polling_rate') ??
        'Standard (5s)';
    _screenWakeup = await StorageService.getBool(
      'setting_screen_wakeup',
      defaultValue: true,
    );
    _statusBarTicker = await StorageService.getBool(
      'setting_status_bar_ticker',
      defaultValue: true,
    );
    _deadManWarning = await StorageService.getBool(
      'setting_deadman_warning',
      defaultValue: true,
    );
    _autoNetworkFailover = await StorageService.getBool(
      'setting_network_failover',
      defaultValue: true,
    );
    _lowBatteryGuard = await StorageService.getBool(
      'setting_low_battery_guard',
      defaultValue: true,
    );

    // 3. AI
    _llmTemperature = await StorageService.getDouble(
      'setting_llm_temp',
      defaultValue: 0.20,
    );
    // The output budget is fixed for all users; overwrite any old saved value.
    _llmMaxTokens = 8000;
    await StorageService.setInt('setting_llm_tokens', 8000);
    _aiExecutionStrategy =
        await StorageService.getString('setting_ai_strategy') ?? 'Parallel';
    _aiTraderDirective =
        await StorageService.getString('setting_ai_directive') ?? '';

    // 4. Market Data
    _biquoteAutoReconnect = await StorageService.getBool(
      'setting_biquote_reconnect',
      defaultValue: true,
    );
    _directIpFallback = await StorageService.getBool(
      'setting_direct_ip_fallback',
      defaultValue: true,
    );
    _tradingTimezone =
        await StorageService.getString('setting_trading_timezone') ??
        'UTC / GMT';
    _transportFallback = await StorageService.getBool(
      'setting_transport_fallback',
      defaultValue: true,
    );
    _showSpreadDisplay = await StorageService.getBool(
      'setting_show_spread',
      defaultValue: true,
    );
    final savedSessions = await StorageService.getString(
      'setting_trading_sessions',
    );
    if (savedSessions != null && savedSessions.isNotEmpty) {
      _selectedSessions = savedSessions.split('|||');
    }
    _sessionAlertTiming =
        await StorageService.getString('setting_session_timing') ??
        'At Session Open';

    // 5. Trigger & Snooze
    _defaultSnoozeMinutes = await StorageService.getInt(
      'setting_default_snooze',
      defaultValue: 5,
    );
    _alertTtl = await StorageService.getString('setting_alert_ttl') ?? 'Never';

    // 6. Chart & Terminal
    _defaultLaunchScreen =
        await StorageService.getString('setting_launch_screen') ??
        'Market Watch';
    if (_defaultLaunchScreen == 'Economic Calendar') {
      _defaultLaunchScreen = 'Markets Hub';
      await StorageService.setString(
        'setting_launch_screen',
        _defaultLaunchScreen,
      );
    }
    _defaultChartTimeframe =
        await StorageService.getString('setting_chart_tf') ?? '15m';
    _chartCandleType =
        await StorageService.getString('setting_candle_type') ??
        'Japanese Candles';
    _showCandleCountdown = await StorageService.getBool(
      'setting_candle_countdown',
      defaultValue: true,
    );
    _vibrateOnDrag = await StorageService.getBool(
      'setting_vibrate_drag',
      defaultValue: true,
    );
    _magneticSnapping = await StorageService.getBool(
      'setting_magnetic_snapping',
      defaultValue: true,
    );
    _sessionShading = await StorageService.getBool(
      'setting_session_shading',
      defaultValue: true,
    );
    _colorblindChartMode =
        await StorageService.getString('setting_colorblind_mode') ?? 'Standard';

    // 7. Data & System
    _biometricAppLock = await StorageService.getBool(
      'setting_biometric_lock',
      defaultValue: false,
    );

    _isLoaded = true;
    notifyListeners();
  }

  // Setters with persistence and reactivity
  Future<void> setSound(String title, String uri) async {
    _soundTitle = title;
    _soundUri = uri;
    await StorageService.setString('setting_global_sound_title', title);
    await StorageService.setString('setting_global_sound_uri', uri);
    notifyListeners();
  }

  Future<void> setAlarmVolume(double volume) async {
    _alarmVolume = volume;
    await StorageService.setDouble('setting_alarm_volume', volume);
    notifyListeners();
  }

  Future<void> setForceMaxVolume(bool value) async {
    _forceMaxVolume = value;
    await StorageService.setBool('setting_force_max_vol', value);
    notifyListeners();
  }

  Future<void> setVolumeEscalation(bool value) async {
    _volumeEscalation = value;
    await StorageService.setBool('setting_volume_escalation', value);
    notifyListeners();
  }

  Future<void> setQuietHoursEnabled(bool value) async {
    _quietHoursEnabled = value;
    await StorageService.setBool('setting_quiet_hours_enabled', value);
    notifyListeners();
  }

  Future<void> setQuietHours(String schedule) async {
    _quietHours = schedule;
    await StorageService.setString('setting_quiet_hours', schedule);
    notifyListeners();
  }

  Future<void> setQuietHoursVolume(double volume) async {
    _quietHoursVolume = volume;
    await StorageService.setDouble('setting_quiet_hours_vol', volume);
    notifyListeners();
  }

  Future<void> setQuietHoursBypassCritical(bool value) async {
    _quietHoursBypassCritical = value;
    await StorageService.setBool('setting_quiet_bypass', value);
    notifyListeners();
  }

  Future<void> setVibrationMode(String mode) async {
    _vibrationMode = mode;
    await StorageService.setString('setting_vibration_mode', mode);
    notifyListeners();
  }

  Future<void> setAlarmAutoSilence(String value) async {
    _alarmAutoSilence = value;
    await StorageService.setString('setting_auto_silence', value);
    notifyListeners();
  }

  Future<void> setTtsEnabled(bool value) async {
    _ttsEnabled = value;
    await StorageService.setBool('setting_tts_enabled', value);
    notifyListeners();
  }

  Future<void> setTtsSpeechRate(String rate) async {
    _ttsSpeechRate = rate;
    await StorageService.setString('setting_tts_rate', rate);
    notifyListeners();
  }

  Future<void> setAudioDucking(bool value) async {
    _audioDucking = value;
    await StorageService.setBool('setting_audio_ducking', value);
    notifyListeners();
  }

  Future<void> setFlashlightStrobe(bool value) async {
    _flashlightStrobe = value;
    await StorageService.setBool('setting_flashlight_strobe', value);
    notifyListeners();
  }

  Future<void> setHeadphoneSafety(bool value) async {
    _headphoneSafety = value;
    await StorageService.setBool('setting_headphone_safety', value);
    notifyListeners();
  }

  Future<void> setPerpetualServiceActive(bool value) async {
    _perpetualServiceActive = value;
    await StorageService.setBool('setting_perpetual_service', value);
    notifyListeners();
  }

  Future<void> setPollingRate(String rate) async {
    _pollingRate = rate;
    await StorageService.setString('setting_polling_rate', rate);
    notifyListeners();
  }

  Future<void> setScreenWakeup(bool value) async {
    _screenWakeup = value;
    await StorageService.setBool('setting_screen_wakeup', value);
    notifyListeners();
  }

  Future<void> setStatusBarTicker(bool value) async {
    _statusBarTicker = value;
    await StorageService.setBool('setting_status_bar_ticker', value);
    notifyListeners();
  }

  Future<void> setDeadManWarning(bool value) async {
    _deadManWarning = value;
    await StorageService.setBool('setting_deadman_warning', value);
    notifyListeners();
  }

  Future<void> setAutoNetworkFailover(bool value) async {
    _autoNetworkFailover = value;
    await StorageService.setBool('setting_network_failover', value);
    notifyListeners();
  }

  Future<void> setLowBatteryGuard(bool value) async {
    _lowBatteryGuard = value;
    await StorageService.setBool('setting_low_battery_guard', value);
    notifyListeners();
  }

  Future<void> setLlmTemperature(double temp) async {
    _llmTemperature = temp;
    await StorageService.setDouble('setting_llm_temp', temp);
    notifyListeners();
  }

  Future<void> setLlmMaxTokens(int tokens) async {
    _llmMaxTokens = 8000;
    await StorageService.setInt('setting_llm_tokens', 8000);
    notifyListeners();
  }

  Future<void> setAiExecutionStrategy(String strategy) async {
    _aiExecutionStrategy = strategy;
    await StorageService.setString('setting_ai_strategy', strategy);
    notifyListeners();
  }

  Future<void> setAiTraderDirective(String directive) async {
    _aiTraderDirective = directive;
    await StorageService.setString('setting_ai_directive', directive);
    notifyListeners();
  }

  Future<void> setBiquoteAutoReconnect(bool value) async {
    _biquoteAutoReconnect = value;
    await StorageService.setBool('setting_biquote_reconnect', value);
    notifyListeners();
  }

  Future<void> setDirectIpFallback(bool value) async {
    _directIpFallback = value;
    await StorageService.setBool('setting_direct_ip_fallback', value);
    notifyListeners();
  }

  Future<void> setTradingTimezone(String tz) async {
    _tradingTimezone = tz;
    await StorageService.setString('setting_trading_timezone', tz);
    notifyListeners();
  }

  Future<void> setTransportFallback(bool value) async {
    _transportFallback = value;
    await StorageService.setBool('setting_transport_fallback', value);
    notifyListeners();
  }

  Future<void> setShowSpreadDisplay(bool value) async {
    _showSpreadDisplay = value;
    await StorageService.setBool('setting_show_spread', value);
    notifyListeners();
  }

  /// Accepts the legacy setting without applying a cache limit.
  Future<void> setOfflineCandleRetention(String retention) async {
    _offlineCandleRetention = retention;
    notifyListeners();
  }

  Future<void> setSelectedSessions(List<String> sessions) async {
    _selectedSessions = List.from(sessions);
    await StorageService.setString(
      'setting_trading_sessions',
      sessions.join('|||'),
    );
    notifyListeners();
  }

  Future<void> setSessionAlertTiming(String timing) async {
    _sessionAlertTiming = timing;
    await StorageService.setString('setting_session_timing', timing);
    notifyListeners();
  }

  Future<void> setDefaultSnoozeMinutes(int minutes) async {
    _defaultSnoozeMinutes = minutes;
    await StorageService.setInt('setting_default_snooze', minutes);
    notifyListeners();
  }

  Future<void> setAlertTtl(String ttl) async {
    _alertTtl = ttl;
    await StorageService.setString('setting_alert_ttl', ttl);
    notifyListeners();
  }

  Future<void> setDefaultLaunchScreen(String screen) async {
    _defaultLaunchScreen = screen;
    await StorageService.setString('setting_launch_screen', screen);
    notifyListeners();
  }

  Future<void> setDefaultChartTimeframe(String tf) async {
    _defaultChartTimeframe = tf;
    await StorageService.setString('setting_chart_tf', tf);
    notifyListeners();
  }

  Future<void> setChartCandleType(String type) async {
    _chartCandleType = type;
    await StorageService.setString('setting_candle_type', type);
    notifyListeners();
  }

  Future<void> setShowCandleCountdown(bool value) async {
    _showCandleCountdown = value;
    await StorageService.setBool('setting_candle_countdown', value);
    notifyListeners();
  }

  Future<void> setVibrateOnDrag(bool value) async {
    _vibrateOnDrag = value;
    await StorageService.setBool('setting_vibrate_drag', value);
    notifyListeners();
  }

  Future<void> setMagneticSnapping(bool value) async {
    _magneticSnapping = value;
    await StorageService.setBool('setting_magnetic_snapping', value);
    notifyListeners();
  }

  Future<void> setSessionShading(bool value) async {
    _sessionShading = value;
    await StorageService.setBool('setting_session_shading', value);
    notifyListeners();
  }

  Future<void> setColorblindChartMode(String mode) async {
    _colorblindChartMode = mode;
    await StorageService.setString('setting_colorblind_mode', mode);
    notifyListeners();
  }

  Future<void> setBiometricAppLock(bool value) async {
    _biometricAppLock = value;
    await StorageService.setBool('setting_biometric_lock', value);
    notifyListeners();
  }

  /// Exports all settings as a JSON map
  Map<String, dynamic> exportSettingsToJson() {
    return {
      'soundTitle': _soundTitle,
      'soundUri': _soundUri,
      'alarmVolume': _alarmVolume,
      'forceMaxVolume': _forceMaxVolume,
      'volumeEscalation': _volumeEscalation,
      'quietHoursEnabled': _quietHoursEnabled,
      'quietHours': _quietHours,
      'quietHoursVolume': _quietHoursVolume,
      'quietHoursBypassCritical': _quietHoursBypassCritical,
      'vibrationMode': _vibrationMode,
      'alarmAutoSilence': _alarmAutoSilence,
      'ttsEnabled': _ttsEnabled,
      'ttsSpeechRate': _ttsSpeechRate,
      'audioDucking': _audioDucking,
      'flashlightStrobe': _flashlightStrobe,
      'headphoneSafety': _headphoneSafety,
      'perpetualServiceActive': _perpetualServiceActive,
      'pollingRate': _pollingRate,
      'screenWakeup': _screenWakeup,
      'statusBarTicker': _statusBarTicker,
      'deadManWarning': _deadManWarning,
      'autoNetworkFailover': _autoNetworkFailover,
      'lowBatteryGuard': _lowBatteryGuard,
      'llmTemperature': _llmTemperature,
      'llmMaxTokens': _llmMaxTokens,
      'aiExecutionStrategy': _aiExecutionStrategy,
      'aiTraderDirective': _aiTraderDirective,
      'biquoteAutoReconnect': _biquoteAutoReconnect,
      'directIpFallback': _directIpFallback,
      'tradingTimezone': _tradingTimezone,
      'transportFallback': _transportFallback,
      'showSpreadDisplay': _showSpreadDisplay,
      'selectedSessions': _selectedSessions,
      'sessionAlertTiming': _sessionAlertTiming,
      'defaultSnoozeMinutes': _defaultSnoozeMinutes,
      'alertTtl': _alertTtl,
      'defaultLaunchScreen': _defaultLaunchScreen,
      'defaultChartTimeframe': _defaultChartTimeframe,
      'chartCandleType': _chartCandleType,
      'showCandleCountdown': _showCandleCountdown,
      'vibrateOnDrag': _vibrateOnDrag,
      'magneticSnapping': _magneticSnapping,
      'sessionShading': _sessionShading,
      'colorblindChartMode': _colorblindChartMode,
      'biometricAppLock': _biometricAppLock,
    };
  }

  /// Restores all settings from a JSON map
  static void validateSettingsImport(Map<String, dynamic> map) {
    const boolKeys = {
      'forceMaxVolume',
      'volumeEscalation',
      'quietHoursEnabled',
      'quietHoursBypassCritical',
      'ttsEnabled',
      'audioDucking',
      'flashlightStrobe',
      'headphoneSafety',
      'perpetualServiceActive',
      'screenWakeup',
      'statusBarTicker',
      'deadManWarning',
      'autoNetworkFailover',
      'lowBatteryGuard',
      'biquoteAutoReconnect',
      'directIpFallback',
      'showSpreadDisplay',
      'showCandleCountdown',
      'vibrateOnDrag',
      'magneticSnapping',
      'sessionShading',
      'biometricAppLock',
    };
    const numberKeys = {'alarmVolume', 'quietHoursVolume', 'llmTemperature'};
    const stringKeys = {
      'soundTitle',
      'soundUri',
      'quietHours',
      'vibrationMode',
      'alarmAutoSilence',
      'ttsSpeechRate',
      'pollingRate',
      'aiExecutionStrategy',
      'aiTraderDirective',
      'tradingTimezone',
      'transportFallback',
      'sessionAlertTiming',
      'alertTtl',
      'defaultLaunchScreen',
      'defaultChartTimeframe',
      'chartCandleType',
      'colorblindChartMode',
    };
    for (final key in boolKeys) {
      if (map.containsKey(key) && map[key] is! bool) {
        throw FormatException('Setting $key must be a boolean');
      }
    }
    for (final key in numberKeys) {
      if (map.containsKey(key) && map[key] is! num) {
        throw FormatException('Setting $key must be numeric');
      }
    }
    for (final key in stringKeys) {
      if (map.containsKey(key) && map[key] is! String) {
        throw FormatException('Setting $key must be text');
      }
    }
    if (map['llmMaxTokens'] != null && map['llmMaxTokens'] is! int) {
      throw const FormatException('llmMaxTokens must be an integer');
    }
    if (map['defaultSnoozeMinutes'] != null &&
        map['defaultSnoozeMinutes'] is! int) {
      throw const FormatException('defaultSnoozeMinutes must be an integer');
    }
    if (map['selectedSessions'] != null &&
        (map['selectedSessions'] is! List ||
            (map['selectedSessions'] as List).any((item) => item is! String))) {
      throw const FormatException('selectedSessions must be a list of text');
    }
  }

  Future<void> importSettingsFromJson(Map<String, dynamic> map) async {
    if (map['soundTitle'] != null) {
      await setSound(map['soundTitle'], map['soundUri'] ?? 'default_alarm');
    }
    if (map['alarmVolume'] != null) {
      await setAlarmVolume((map['alarmVolume'] as num).toDouble());
    }
    if (map['forceMaxVolume'] != null) {
      await setForceMaxVolume(map['forceMaxVolume'] as bool);
    }
    if (map['volumeEscalation'] != null) {
      await setVolumeEscalation(map['volumeEscalation'] as bool);
    }
    if (map['quietHoursEnabled'] != null) {
      await setQuietHoursEnabled(map['quietHoursEnabled'] as bool);
    }
    if (map['quietHours'] != null) {
      await setQuietHours(map['quietHours'].toString());
    }
    if (map['quietHoursVolume'] != null) {
      await setQuietHoursVolume((map['quietHoursVolume'] as num).toDouble());
    }
    if (map['quietHoursBypassCritical'] != null) {
      await setQuietHoursBypassCritical(
        map['quietHoursBypassCritical'] as bool,
      );
    }
    if (map['vibrationMode'] != null) {
      await setVibrationMode(map['vibrationMode'].toString());
    }
    if (map['alarmAutoSilence'] != null) {
      await setAlarmAutoSilence(map['alarmAutoSilence'].toString());
    }
    if (map['ttsEnabled'] != null) {
      await setTtsEnabled(map['ttsEnabled'] as bool);
    }
    if (map['ttsSpeechRate'] != null) {
      await setTtsSpeechRate(map['ttsSpeechRate'].toString());
    }
    if (map['audioDucking'] != null) {
      await setAudioDucking(map['audioDucking'] as bool);
    }
    if (map['flashlightStrobe'] != null) {
      await setFlashlightStrobe(map['flashlightStrobe'] as bool);
    }
    if (map['headphoneSafety'] != null) {
      await setHeadphoneSafety(map['headphoneSafety'] as bool);
    }

    if (map['perpetualServiceActive'] != null) {
      await setPerpetualServiceActive(map['perpetualServiceActive'] as bool);
    }
    if (map['pollingRate'] != null) {
      await setPollingRate(map['pollingRate'].toString());
    }
    if (map['screenWakeup'] != null) {
      await setScreenWakeup(map['screenWakeup'] as bool);
    }
    if (map['statusBarTicker'] != null) {
      await setStatusBarTicker(map['statusBarTicker'] as bool);
    }
    if (map['deadManWarning'] != null) {
      await setDeadManWarning(map['deadManWarning'] as bool);
    }
    if (map['autoNetworkFailover'] != null) {
      await setAutoNetworkFailover(map['autoNetworkFailover'] as bool);
    }
    if (map['lowBatteryGuard'] != null) {
      await setLowBatteryGuard(map['lowBatteryGuard'] as bool);
    }

    if (map['llmTemperature'] != null) {
      await setLlmTemperature((map['llmTemperature'] as num).toDouble());
    }
    if (map['llmMaxTokens'] != null) {
      await setLlmMaxTokens(map['llmMaxTokens'] as int);
    }
    if (map['aiExecutionStrategy'] != null) {
      await setAiExecutionStrategy(map['aiExecutionStrategy'].toString());
    }
    if (map['aiTraderDirective'] != null) {
      await setAiTraderDirective(map['aiTraderDirective'].toString());
    }

    if (map['biquoteAutoReconnect'] != null) {
      await setBiquoteAutoReconnect(map['biquoteAutoReconnect'] as bool);
    }
    if (map['directIpFallback'] != null) {
      await setDirectIpFallback(map['directIpFallback'] as bool);
    }
    if (map['tradingTimezone'] != null) {
      await setTradingTimezone(map['tradingTimezone'].toString());
    }
    if (map['transportFallback'] != null) {
      await setTransportFallback(map['transportFallback'] as bool);
    }
    if (map['showSpreadDisplay'] != null) {
      await setShowSpreadDisplay(map['showSpreadDisplay'] as bool);
    }
    if (map['selectedSessions'] != null) {
      await setSelectedSessions(
        (map['selectedSessions'] as List).map((e) => e.toString()).toList(),
      );
    }
    if (map['sessionAlertTiming'] != null) {
      await setSessionAlertTiming(map['sessionAlertTiming'].toString());
    }

    if (map['defaultSnoozeMinutes'] != null) {
      await setDefaultSnoozeMinutes(map['defaultSnoozeMinutes'] as int);
    }
    if (map['alertTtl'] != null) await setAlertTtl(map['alertTtl'].toString());

    if (map['defaultLaunchScreen'] != null) {
      await setDefaultLaunchScreen(map['defaultLaunchScreen'].toString());
    }
    if (map['defaultChartTimeframe'] != null) {
      await setDefaultChartTimeframe(map['defaultChartTimeframe'].toString());
    }
    if (map['chartCandleType'] != null) {
      await setChartCandleType(map['chartCandleType'].toString());
    }
    if (map['showCandleCountdown'] != null) {
      await setShowCandleCountdown(map['showCandleCountdown'] as bool);
    }
    if (map['vibrateOnDrag'] != null) {
      await setVibrateOnDrag(map['vibrateOnDrag'] as bool);
    }
    if (map['magneticSnapping'] != null) {
      await setMagneticSnapping(map['magneticSnapping'] as bool);
    }
    if (map['sessionShading'] != null) {
      await setSessionShading(map['sessionShading'] as bool);
    }
    if (map['colorblindChartMode'] != null) {
      await setColorblindChartMode(map['colorblindChartMode'].toString());
    }
    if (map['biometricAppLock'] != null) {
      await setBiometricAppLock(map['biometricAppLock'] as bool);
    }
  }

  /// Resets all global settings back to original factory defaults
  Future<void> resetToDefaults() async {
    await setSound('System default', 'default_alarm');
    await setAlarmVolume(0.85);
    await setForceMaxVolume(false);
    await setVolumeEscalation(true);
    await setQuietHoursEnabled(true);
    await setQuietHours('23:00 – 07:00');
    await setQuietHoursVolume(0.25);
    await setQuietHoursBypassCritical(true);
    await setVibrationMode('Continuous');
    await setAlarmAutoSilence('Never');
    await setTtsEnabled(false);
    await setTtsSpeechRate('1.0x');
    await setAudioDucking(true);
    await setFlashlightStrobe(false);
    await setHeadphoneSafety(true);

    await setPerpetualServiceActive(true);
    await setPollingRate('Standard (5s)');
    await setScreenWakeup(true);
    await setStatusBarTicker(true);
    await setDeadManWarning(true);
    await setAutoNetworkFailover(true);
    await setLowBatteryGuard(true);

    await setLlmTemperature(0.20);
    await setLlmMaxTokens(8000);
    await setAiExecutionStrategy('Parallel');
    await setAiTraderDirective('');

    await setBiquoteAutoReconnect(true);
    await setDirectIpFallback(true);
    await setTradingTimezone('UTC / GMT');
    await setTransportFallback(true);
    await setShowSpreadDisplay(true);
    await setSelectedSessions([
      'London Open (07:00 UTC)',
      'New York Open (12:00 UTC)',
    ]);
    await setSessionAlertTiming('At Session Open');

    await setDefaultSnoozeMinutes(5);
    await setAlertTtl('Never');

    await setDefaultLaunchScreen('Market Watch');
    await setDefaultChartTimeframe('15m');
    await setChartCandleType('Japanese Candles');
    await setShowCandleCountdown(true);
    await setVibrateOnDrag(true);
    await setMagneticSnapping(true);
    await setSessionShading(true);
    await setColorblindChartMode('Standard');

    await setBiometricAppLock(false);
  }
}
