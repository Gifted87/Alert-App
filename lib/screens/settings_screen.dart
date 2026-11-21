import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/api_config.dart';
import '../services/ai_service.dart';
import '../services/app_remote_config.dart';
import '../services/alarm_service.dart';
import '../services/alert_manager.dart';
import '../services/biquote_service.dart';
import '../services/realmarket_service.dart';
import '../services/strategy_storage.dart';
import '../services/settings_provider.dart';
import '../services/storage_service.dart';
import '../widgets/tenx_toast.dart';

class _SettingsCategoryInfo {
  final String title;
  final String subtitle;
  final IconData icon;
  final String section;

  const _SettingsCategoryInfo(
    this.title,
    this.subtitle,
    this.icon,
    this.section,
  );
}

class _SettingsSearchItem {
  final String title;
  final String category;
  final String description;

  const _SettingsSearchItem(this.title, this.category, [this.description = '']);
}

class _SettingsSubgroup extends StatelessWidget {
  final String title;

  const _SettingsSubgroup(this.title);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class SettingsScreen extends StatefulWidget {
  final bool? isDark;
  final VoidCallback? onToggleTheme;
  final AlertManager? alertManager;
  final BiquoteService? biquoteService;
  final String? initialCategory;
  final String? initialSearchTarget;
  final VoidCallback? onManageAccount;

  const SettingsScreen({
    super.key,
    this.isDark,
    this.onToggleTheme,
    this.alertManager,
    this.biquoteService,
    this.initialCategory,
    this.initialSearchTarget,
    this.onManageAccount,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  static const _categories = <_SettingsCategoryInfo>[
    _SettingsCategoryInfo(
      'Market Data',
      'Feeds, quotes, candles and sessions',
      Icons.show_chart_rounded,
      'MARKET DATA',
    ),
    _SettingsCategoryInfo(
      'Background Monitoring',
      'Monitoring, permissions and connection recovery',
      Icons.sync_rounded,
      'BACKGROUND MONITORING',
    ),
    _SettingsCategoryInfo(
      'Alarms & Audio',
      'Sound, vibration and alert playback',
      Icons.notifications_active_rounded,
      'ALARMS & AUDIO',
    ),
    _SettingsCategoryInfo(
      'Alerts & Snooze',
      'Snooze and alert expiration behavior',
      Icons.snooze_rounded,
      'ALERTS & SNOOZE',
    ),
    _SettingsCategoryInfo(
      'AI Deliberation',
      'Inference model and execution preferences',
      Icons.psychology_rounded,
      'AI DELIBERATION',
    ),
    _SettingsCategoryInfo(
      'Charts & Terminal',
      'Chart defaults, drawing and display options',
      Icons.candlestick_chart_rounded,
      'CHARTS & TERMINAL',
    ),
    _SettingsCategoryInfo(
      'Data & Backup',
      'Backups, diagnostics and device data',
      Icons.storage_rounded,
      'DATA & BACKUP',
    ),
    _SettingsCategoryInfo(
      'About',
      'App version and information',
      Icons.info_outline_rounded,
      'ABOUT',
    ),
  ];

  static const _searchItems = <_SettingsSearchItem>[
    _SettingsSearchItem(
      'Biquote feed',
      'MARKET DATA',
      'Market quotes and live data connection',
    ),
    _SettingsSearchItem(
      'Automatic reconnect',
      'MARKET DATA',
      'Resubscribe WebSocket channels upon reconnection',
    ),
    _SettingsSearchItem(
      'Direct IP fallback',
      'MARKET DATA',
      'Retry Biquote over its fixed IP when domain DNS fails',
    ),
    _SettingsSearchItem(
      'REST quote fallback',
      'MARKET DATA',
      'Poll quotes when SignalR is unavailable',
    ),
    _SettingsSearchItem(
      'App-wide historical candles provider',
      'MARKET DATA',
      'Historical chart candles and API credentials',
    ),
    _SettingsSearchItem(
      'Global trading timezone',
      'MARKET DATA',
      'Timezone used for trading sessions',
    ),
    _SettingsSearchItem(
      'Live feed spread display',
      'MARKET DATA',
      'Show Biquote bid ask spread on the chart',
    ),
    _SettingsSearchItem(
      'Session open alerts',
      'MARKET DATA',
      'Notify when London, New York, or Asian markets open',
    ),
    _SettingsSearchItem(
      'Perpetual monitoring service',
      'BACKGROUND MONITORING',
      'Keep alerts active when app is closed or device is locked',
    ),
    _SettingsSearchItem(
      'Battery optimization',
      'BACKGROUND MONITORING',
      'Prevent Android from putting background monitoring to sleep',
    ),
    _SettingsSearchItem(
      'Bypass Do Not Disturb',
      'BACKGROUND MONITORING',
      'Allow critical price alarms to sound on silent',
    ),
    _SettingsSearchItem(
      'Full-screen lock-screen access',
      'BACKGROUND MONITORING',
      'Android permission for alert screens over the lock screen',
    ),
    _SettingsSearchItem(
      'Polling frequency',
      'BACKGROUND MONITORING',
      'How often TenX checks market prices',
    ),
    _SettingsSearchItem(
      'Wake screen on alert',
      'BACKGROUND MONITORING',
      'Turn on the display when an alert fires',
    ),
    _SettingsSearchItem(
      'Persistent price notification',
      'BACKGROUND MONITORING',
      'Show a live quote in Android notifications while monitoring',
    ),
    _SettingsSearchItem(
      'Connection loss warning',
      'BACKGROUND MONITORING',
      'Sound alarm if internet drops for over 3 minutes',
    ),
    _SettingsSearchItem(
      'Automatic network failover',
      'BACKGROUND MONITORING',
      'Retry the market socket faster after a network drop',
    ),
    _SettingsSearchItem(
      'Low battery alert protection',
      'BACKGROUND MONITORING',
      'Notify at 15 percent or below and reduce market checks',
    ),
    _SettingsSearchItem(
      'Alarm ringtone',
      'ALARMS & AUDIO',
      'Choose the sound played when alerts trigger',
    ),
    _SettingsSearchItem(
      'Uploaded audio library',
      'ALARMS & AUDIO',
      'Manage user imported sound clips',
    ),
    _SettingsSearchItem(
      'Force maximum volume',
      'ALARMS & AUDIO',
      'Sound at full volume regardless of system slider',
    ),
    _SettingsSearchItem(
      'Gradual volume escalation',
      'ALARMS & AUDIO',
      'Start quietly and raise alarm volume over time',
    ),
    _SettingsSearchItem(
      'Quiet hours',
      'ALARMS & AUDIO',
      'Reduce alarm volume during scheduled quiet time',
    ),
    _SettingsSearchItem(
      'Vibration rhythm',
      'ALARMS & AUDIO',
      'Choose the vibration pattern for alerts',
    ),
    _SettingsSearchItem(
      'Auto-silence duration',
      'ALARMS & AUDIO',
      'Stop alarm sound automatically after a duration',
    ),
    _SettingsSearchItem(
      'Voice announcements',
      'ALARMS & AUDIO',
      'Speak symbol and target price aloud when triggered',
    ),
    _SettingsSearchItem(
      'Voice speech rate',
      'ALARMS & AUDIO',
      'Adjust spoken alert speed',
    ),
    _SettingsSearchItem(
      'Audio ducking',
      'ALARMS & AUDIO',
      'Request Android audio focus so other playback can duck during alarms',
    ),
    _SettingsSearchItem(
      'Flashlight strobe alert',
      'ALARMS & AUDIO',
      'Pulse camera flash in sync with alarm vibrations',
    ),
    _SettingsSearchItem(
      'Connected audio volume limiter',
      'ALARMS & AUDIO',
      'Limit alarm volume on wired, USB, and Bluetooth audio',
    ),
    _SettingsSearchItem(
      'Default snooze duration',
      'ALERTS & SNOOZE',
      'Choose how long alerts snooze',
    ),
    _SettingsSearchItem(
      'Stale alert expiration',
      'ALERTS & SNOOZE',
      'Automatically deactivate unhit price alerts after period',
    ),
    _SettingsSearchItem(
      'App-wide AI provider',
      'AI DELIBERATION',
      'AI model API URL, key, and model name',
    ),
    _SettingsSearchItem(
      'Execution strategy',
      'AI DELIBERATION',
      'Choose how AI analysis runs',
    ),
    _SettingsSearchItem(
      'Temperature',
      'AI DELIBERATION',
      'Control AI response creativity',
    ),
    _SettingsSearchItem(
      'Default launch screen',
      'CHARTS & TERMINAL',
      'Choose which screen opens when TenX starts',
    ),
    _SettingsSearchItem(
      'Default timeframe',
      'CHARTS & TERMINAL',
      'Initial chart timeframe',
    ),
    _SettingsSearchItem(
      'Candlestick style',
      'CHARTS & TERMINAL',
      'Choose chart candle appearance',
    ),
    _SettingsSearchItem(
      'Candle countdown timer',
      'CHARTS & TERMINAL',
      'Display remaining time until current bar closes',
    ),
    _SettingsSearchItem(
      'Tactile line drag',
      'CHARTS & TERMINAL',
      'Haptic feedback while dragging chart lines or crosshair',
    ),
    _SettingsSearchItem(
      'Magnetic snapping',
      'CHARTS & TERMINAL',
      'Snap chart lines to candle OHLC values and nearby round prices',
    ),
    _SettingsSearchItem(
      'Market session shading',
      'CHARTS & TERMINAL',
      'Render highlights for Tokyo, London, and New York hours',
    ),
    _SettingsSearchItem(
      'Color palette mode',
      'CHARTS & TERMINAL',
      'Choose chart colors and accessibility palette',
    ),
    _SettingsSearchItem(
      'Export backup',
      'DATA & BACKUP',
      'Save a full JSON backup of settings and strategies',
    ),
    _SettingsSearchItem(
      'Restore backup',
      'DATA & BACKUP',
      'Import settings from a backup file',
    ),
    _SettingsSearchItem(
      'Biometric app lock',
      'DATA & BACKUP',
      'Protect the app with biometrics or device PIN',
    ),
    _SettingsSearchItem(
      'Export trading journal',
      'DATA & BACKUP',
      'Copy alert history and AI specialist votes to CSV',
    ),
    _SettingsSearchItem(
      'System diagnostics ping',
      'DATA & BACKUP',
      'Check SignalR, candles, AI, and daemon status',
    ),
    _SettingsSearchItem(
      'Device telemetry',
      'DATA & BACKUP',
      'Inspect operating system, daemon PID, and memory',
    ),
    _SettingsSearchItem(
      'Share diagnostic log',
      'DATA & BACKUP',
      'Share a sanitized diagnostic report',
    ),
    _SettingsSearchItem(
      'Clear candle cache',
      'DATA & BACKUP',
      'Purge locally cached historical candles',
    ),
    _SettingsSearchItem(
      'Clear alert history',
      'DATA & BACKUP',
      'Purge triggered records without affecting active alerts',
    ),
    _SettingsSearchItem(
      'Reset to factory defaults',
      'DATA & BACKUP',
      'Reset all app settings to defaults',
    ),
    _SettingsSearchItem(
      'Version',
      'ABOUT',
      'App version and build information',
    ),
    _SettingsSearchItem('Built by', 'ABOUT', 'Gift Braimah, app creator'),
  ];

  final StrategyStorage _storage = StrategyStorage();
  final AiService _aiService = AiService();
  final RealMarketService _realMarketService = RealMarketService();
  late final AlarmService _alarmService;

  bool _isLoading = true;
  final TextEditingController _settingsSearchController =
      TextEditingController();
  final Map<String, GlobalKey> _settingRowKeys = {};

  // 1. Audio & Sounds
  String _selectedSoundTitle = 'System default';
  String _selectedSoundUri = 'default_alarm';
  double _alarmVolume = 0.85;
  bool _forceMaxVolume = false;
  bool _volumeEscalation = true;
  bool _quietHoursEnabled = true;
  String _quietHours = '23:00 – 07:00';
  double _quietHoursVolume = 0.25;
  bool _quietHoursBypassCritical = true;
  String _vibrationMode = 'Continuous';
  String _alarmAutoSilence = 'Never';
  bool _ttsEnabled = false;
  String _ttsSpeechRate = '1.0x';
  bool _audioDucking = true;
  bool _flashlightStrobe = false;
  bool _headphoneSafety = true;

  // 2. Background & Permissions
  bool _perpetualServiceActive = true;
  bool _perpetualServiceRunning = false;
  bool _batteryIgnored = false;
  bool _dndGranted = false;
  bool _overlayGranted = false;
  bool _fullScreenIntentAllowed = true;
  String _pollingRate = 'Standard (5s)';
  bool _screenWakeup = true;
  bool _statusBarTicker = true;
  bool _deadManWarning = true;
  bool _autoNetworkFailover = true;
  bool _lowBatteryGuard = true;

  // 3. AI Deliberation
  double _llmTemperature = 0.20;
  String _aiExecutionStrategy = 'Parallel';
  late TextEditingController _aiTraderDirectiveController;

  // 4. Market Data
  bool _biquoteAutoReconnect = true;
  String _biquoteLatency = 'Checking…';
  bool _directIpFallback = true;
  String _tradingTimezone = 'UTC / GMT';
  bool _transportFallback = true;
  bool _showSpreadDisplay = true;
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
  String _chartCandleType = 'Japanese Candles';
  bool _showCandleCountdown = true;
  bool _vibrateOnDrag = true;
  bool _magneticSnapping = true;
  bool _sessionShading = true;
  String _colorblindChartMode = 'Standard';

  // 7. Data & System
  bool _biometricAppLock = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SettingsProvider().addListener(_onGlobalSettingsChanged);
    _alarmService = widget.alertManager?.alarmService ?? AlarmService();
    _aiTraderDirectiveController = TextEditingController();

    _loadAllSettings().then((_) {
      final target = widget.initialSearchTarget;
      if (target != null && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final targetContext = _settingRowKeys[target]?.currentContext;
          if (targetContext != null) {
            Scrollable.ensureVisible(
              targetContext,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              alignment: 0.25,
            );
          }
        });
      }
    });
    if (widget.initialCategory == null ||
        widget.initialCategory == 'MARKET DATA') {
      _measureBiquoteLatency();
    }
  }

  @override
  void dispose() {
    SettingsProvider().removeListener(_onGlobalSettingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    _aiTraderDirectiveController.dispose();
    _settingsSearchController.dispose();
    super.dispose();
  }

  void _onGlobalSettingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadAllSettings() async {
    final sp = SettingsProvider();
    if (!sp.isLoaded) {
      await sp.loadAll();
    }

    // 1. Audio
    _selectedSoundTitle = sp.soundTitle;
    _selectedSoundUri = sp.soundUri;
    _alarmVolume = sp.alarmVolume;
    _forceMaxVolume = sp.forceMaxVolume;
    _volumeEscalation = sp.volumeEscalation;
    _quietHoursEnabled = sp.quietHoursEnabled;
    _quietHours = sp.quietHours;
    _quietHoursVolume = sp.quietHoursVolume;
    _quietHoursBypassCritical = sp.quietHoursBypassCritical;
    _vibrationMode = sp.vibrationMode;
    _alarmAutoSilence = sp.alarmAutoSilence;
    _ttsEnabled = sp.ttsEnabled;
    _ttsSpeechRate = sp.ttsSpeechRate;
    _audioDucking = sp.audioDucking;
    _flashlightStrobe = sp.flashlightStrobe;
    _headphoneSafety = sp.headphoneSafety;

    // 2. Background
    _batteryIgnored = await _alarmService.isBatteryOptimizationIgnored();
    _dndGranted = await _alarmService.isDndOverrideGranted();
    _overlayGranted = await _alarmService.isOverlayPermissionGranted();
    _fullScreenIntentAllowed = await _alarmService.isFullScreenIntentAllowed();
    _perpetualServiceActive = sp.perpetualServiceActive;
    final telemetry = await _alarmService.getSystemTelemetry();
    _perpetualServiceRunning = telemetry['daemonRunning'] as bool? ?? false;
    _pollingRate = sp.pollingRate;
    _screenWakeup = sp.screenWakeup;
    _statusBarTicker = sp.statusBarTicker;
    _deadManWarning = sp.deadManWarning;
    _autoNetworkFailover = sp.autoNetworkFailover;
    _lowBatteryGuard = sp.lowBatteryGuard;

    // 3. AI
    _llmTemperature = sp.llmTemperature;
    _aiExecutionStrategy = sp.aiExecutionStrategy;
    _aiTraderDirectiveController.text = sp.aiTraderDirective;

    // 4. Market Data
    _biquoteAutoReconnect = sp.biquoteAutoReconnect;
    _directIpFallback = sp.directIpFallback;
    _tradingTimezone = sp.tradingTimezone;
    _transportFallback = sp.transportFallback;
    _showSpreadDisplay = sp.showSpreadDisplay;
    _selectedSessions = List.from(sp.selectedSessions);
    _sessionAlertTiming = sp.sessionAlertTiming;

    // 5. Trigger & Snooze
    _defaultSnoozeMinutes = sp.defaultSnoozeMinutes;
    _alertTtl = sp.alertTtl;

    // 6. Chart & Terminal
    _defaultLaunchScreen = sp.defaultLaunchScreen;
    _defaultChartTimeframe = sp.defaultChartTimeframe;
    _chartCandleType = sp.chartCandleType;
    _showCandleCountdown = sp.showCandleCountdown;
    _vibrateOnDrag = sp.vibrateOnDrag;
    _magneticSnapping = sp.magneticSnapping;
    _sessionShading = sp.sessionShading;
    _colorblindChartMode = sp.colorblindChartMode;

    // 7. Data & System
    _biometricAppLock = sp.biometricAppLock;

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshSystemPermissions();
      _refreshMonitoringStatus();
    }
  }

  Future<void> _refreshMonitoringStatus({bool waitForStart = false}) async {
    for (var attempt = 0; attempt < (waitForStart ? 5 : 1); attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      final telemetry = await _alarmService.getSystemTelemetry();
      final running = telemetry['daemonRunning'] as bool? ?? false;
      if (!mounted) return;
      setState(() => _perpetualServiceRunning = running);
      if (running == _perpetualServiceActive) return;
    }
  }

  Future<void> _refreshSystemPermissions() async {
    final values = await Future.wait([
      _alarmService.isBatteryOptimizationIgnored(),
      _alarmService.isOverlayPermissionGranted(),
      _alarmService.isFullScreenIntentAllowed(),
    ]);
    if (!mounted) return;
    setState(() {
      _batteryIgnored = values[0];
      _overlayGranted = values[1];
      _fullScreenIntentAllowed = values[2];
    });
  }

  Future<void> _measureBiquoteLatency() async {
    final sw = Stopwatch()..start();
    try {
      if (widget.biquoteService != null) {
        final quotes = await widget.biquoteService!
            .getLatestQuotes(['EURUSD'])
            .timeout(const Duration(seconds: 4));
        sw.stop();
        if (mounted) {
          if (quotes.isNotEmpty) {
            setState(() {
              _biquoteLatency = 'API reachable · ${sw.elapsedMilliseconds} ms';
            });
          } else {
            setState(() => _biquoteLatency = 'Feed Standby');
          }
        }
      } else {
        sw.stop();
        if (mounted) {
          setState(() => _biquoteLatency = 'No Service');
        }
      }
    } catch (_) {
      sw.stop();
      if (mounted) {
        setState(() => _biquoteLatency = 'Offline · Unreachable');
      }
    }
  }

  // ==========================================
  // Sound Picker & Custom Upload Library
  // ==========================================
  Future<void> _showSoundPickerSheet() async {
    final ringtones = await _alarmService.getRingtones();
    String? currentPreviewUri;

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          height: MediaQuery.of(ctx).size.height * 0.75,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Alarm Sound',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final uploaded = await _alarmService.pickCustomAudio();
                      if (uploaded != null) {
                        setSheetState(() {
                          ringtones.insert(0, uploaded);
                          currentPreviewUri = uploaded.uri;
                        });
                        setState(() {
                          _selectedSoundTitle = uploaded.title;
                          _selectedSoundUri = uploaded.uri;
                        });
                        SettingsProvider().setSound(
                          uploaded.title,
                          uploaded.uri,
                        );
                        if (!mounted) return;
                        TenXToast.show(
                          context,
                          title: 'Audio Imported',
                          subtitle: uploaded.title,
                        );
                      }
                    },
                    icon: const Icon(
                      Icons.add_rounded,
                      size: 18,
                      color: Color(0xFF0A84FF),
                    ),
                    label: const Text(
                      'Import Audio',
                      style: TextStyle(
                        color: Color(0xFF0A84FF),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Select default alarm chime or import .mp3 / .wav audio.',
                style: TextStyle(fontSize: 13, color: Color(0x9EEBEBF5)),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView.separated(
                  itemCount: ringtones.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (ctx, idx) {
                    final tone = ringtones[idx];
                    final isSelected =
                        tone.uri == _selectedSoundUri ||
                        tone.title == _selectedSoundTitle;
                    final isCustom = tone.type == 'custom';
                    final isPlaying = currentPreviewUri == tone.uri;

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: IconButton(
                        icon: Icon(
                          isPlaying
                              ? Icons.stop_circle_rounded
                              : Icons.play_circle_fill_rounded,
                          color: isSelected
                              ? const Color(0xFF0A84FF)
                              : Colors.white,
                          size: 30,
                        ),
                        onPressed: () {
                          if (isPlaying) {
                            _alarmService.stopPreview();
                            setSheetState(() => currentPreviewUri = null);
                          } else {
                            _alarmService.previewRingtone(tone.uri);
                            setSheetState(() => currentPreviewUri = tone.uri);
                          }
                        },
                      ),
                      title: Text(
                        tone.title,
                        style: TextStyle(
                          color: isSelected
                              ? const Color(0xFF0A84FF)
                              : Colors.white,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Text(
                        isCustom
                            ? 'User imported audio'
                            : (tone.type == 'bundled'
                                  ? 'Bundled TenX tone'
                                  : 'System alert tone'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0x8EEBEBF5),
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isCustom) ...[
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: Color(0xFFFF453A),
                                size: 20,
                              ),
                              onPressed: () async {
                                final deleted = await _alarmService
                                    .deleteCustomAudio(tone.uri);
                                if (deleted) {
                                  setSheetState(() => ringtones.removeAt(idx));
                                  if (!context.mounted) return;
                                  if (_selectedSoundUri == tone.uri) {
                                    setState(() {
                                      _selectedSoundTitle = 'System default';
                                      _selectedSoundUri = 'default_alarm';
                                    });
                                    await SettingsProvider().setSound(
                                      'System default',
                                      'default_alarm',
                                    );
                                    if (!context.mounted) return;
                                  }
                                  if (!mounted) return;
                                  TenXToast.show(
                                    context,
                                    title: 'Audio Removed',
                                    subtitle: tone.title,
                                  );
                                }
                              },
                            ),
                          ],
                          if (isSelected)
                            const Icon(
                              Icons.check_rounded,
                              color: Color(0xFF0A84FF),
                              size: 22,
                            ),
                        ],
                      ),
                      onTap: () {
                        setState(() {
                          _selectedSoundTitle = tone.title;
                          _selectedSoundUri = tone.uri;
                        });
                        SettingsProvider().setSound(tone.title, tone.uri);
                        _alarmService.previewRingtone(tone.uri);
                        setSheetState(() => currentPreviewUri = tone.uri);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    _alarmService.stopPreview();
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2C2C2E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // Quiet Hours Schedule & Ceiling
  // ==========================================
  void _showQuietHoursSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Quiet Hours',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Lowers volume during rest periods while monitoring.',
                style: TextStyle(fontSize: 13, color: Color(0x9EEBEBF5)),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Enable Schedule',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                value: _quietHoursEnabled,
                activeThumbColor: const Color(0xFF30D158),
                onChanged: (v) {
                  setSheetState(() => _quietHoursEnabled = v);
                  setState(() => _quietHoursEnabled = v);
                  SettingsProvider().setQuietHoursEnabled(v);
                },
              ),
              const Text(
                'Schedule Window',
                style: TextStyle(
                  color: Color(0x9EEBEBF5),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              ...['22:00 – 06:00', '23:00 – 07:00', '00:00 – 08:00'].map(
                (schedule) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    schedule,
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: _quietHours == schedule
                      ? const Icon(
                          Icons.check_rounded,
                          color: Color(0xFF0A84FF),
                        )
                      : null,
                  onTap: () {
                    setSheetState(() => _quietHours = schedule);
                    setState(() => _quietHours = schedule);
                    SettingsProvider().setQuietHours(schedule);
                  },
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Bypass for Critical Alerts',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'High-Impact news and Stop-Loss alarms ring at full volume',
                  style: TextStyle(color: Color(0x8EEBEBF5), fontSize: 12),
                ),
                value: _quietHoursBypassCritical,
                activeThumbColor: const Color(0xFF30D158),
                onChanged: (v) {
                  setSheetState(() => _quietHoursBypassCritical = v);
                  setState(() => _quietHoursBypassCritical = v);
                  SettingsProvider().setQuietHoursBypassCritical(v);
                },
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Quiet Hours Volume Limit',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  Text(
                    '${(_quietHoursVolume * 100).toInt()}%',
                    style: const TextStyle(
                      color: Color(0x9EEBEBF5),
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              Slider(
                value: _quietHoursVolume,
                activeColor: const Color(0xFF0A84FF),
                inactiveColor: const Color(0xFF3A3A3C),
                onChanged: (v) {
                  setSheetState(() => _quietHoursVolume = v);
                  setState(() => _quietHoursVolume = v);
                  SettingsProvider().setQuietHoursVolume(v);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // Session Open Alerts Picker
  // ==========================================
  void _showSessionAlertsPicker() {
    final allSessions = [
      'Sydney Open (21:00 UTC)',
      'Tokyo Open (00:00 UTC)',
      'London Open (07:00 UTC)',
      'New York Open (12:00 UTC)',
      'London / NY Overlap (12:00 – 16:00 UTC)',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Session Open Alerts',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Receive alarms when major interbank sessions open.',
                style: TextStyle(fontSize: 12, color: Color(0x9EEBEBF5)),
              ),
              const SizedBox(height: 12),
              ...allSessions.map((s) {
                final isChecked = _selectedSessions.any(
                  (sel) => s.startsWith(sel.split(' ')[0]),
                );
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    s,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  activeColor: const Color(0xFF0A84FF),
                  value: isChecked,
                  onChanged: (val) {
                    setSheetState(() {
                      if (val == true) {
                        _selectedSessions.add(s);
                      } else {
                        _selectedSessions.removeWhere(
                          (item) => item.startsWith(s.split(' ')[0]),
                        );
                      }
                    });
                    setState(() {});
                    SettingsProvider().setSelectedSessions(_selectedSessions);
                  },
                );
              }),
              const Text(
                'Alert Timing',
                style: TextStyle(
                  color: Color(0x9EEBEBF5),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              ...['At Session Open', '5 min before', '15 min before'].map(
                (timing) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    timing,
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: _sessionAlertTiming == timing
                      ? const Icon(
                          Icons.check_rounded,
                          color: Color(0xFF0A84FF),
                        )
                      : null,
                  onTap: () {
                    setSheetState(() => _sessionAlertTiming = timing);
                    setState(() => _sessionAlertTiming = timing);
                    SettingsProvider().setSessionAlertTiming(timing);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // System Diagnostics Ping Suite
  // ==========================================
  Future<void> _runFullDiagnostics() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text(
          'Testing Live Endpoints...',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            LinearProgressIndicator(color: Color(0xFF0A84FF)),
            SizedBox(height: 14),
            Text(
              '1. Biquote SignalR WebSocket & REST...',
              style: TextStyle(color: Color(0x9EEBEBF5), fontSize: 13),
            ),
            SizedBox(height: 4),
            Text(
              '2. RealMarket Candle Feed API...',
              style: TextStyle(color: Color(0x9EEBEBF5), fontSize: 13),
            ),
            SizedBox(height: 4),
            Text(
              '3. LLM Specialist Inference Gateway...',
              style: TextStyle(color: Color(0x9EEBEBF5), fontSize: 13),
            ),
            SizedBox(height: 4),
            Text(
              '4. Android Foreground Daemon & Alarm Watchdog...',
              style: TextStyle(color: Color(0x9EEBEBF5), fontSize: 13),
            ),
          ],
        ),
      ),
    );

    // 1. Live Biquote Ping
    final biquoteWatch = Stopwatch()..start();
    bool biquoteOk = false;
    String biquoteMsg = '';
    try {
      final bq = widget.biquoteService ?? BiquoteService();
      final quotes = await bq
          .getLatestQuotes(['EURUSD'])
          .timeout(const Duration(seconds: 4));
      biquoteWatch.stop();
      if (quotes.isNotEmpty) {
        biquoteOk = true;
        final eurPrice = quotes['EURUSD']?.mid;
        biquoteMsg = eurPrice == null
            ? 'Online (${biquoteWatch.elapsedMilliseconds} ms · No EUR/USD quote returned)'
            : 'Online (${biquoteWatch.elapsedMilliseconds} ms · EUR/USD: $eurPrice)';
      } else {
        biquoteMsg =
            'Online (${biquoteWatch.elapsedMilliseconds} ms · Connected)';
      }
    } catch (e) {
      biquoteWatch.stop();
      biquoteMsg = 'Offline (${biquoteWatch.elapsedMilliseconds} ms · $e)';
    }

    // 2. RealMarket Candle API Ping
    final rmWatch = Stopwatch()..start();
    bool rmOk = false;
    String rmMsg = '';
    try {
      final res = await _realMarketService.testConnection().timeout(
        const Duration(seconds: 4),
      );
      rmWatch.stop();
      rmOk = res.success;
      rmMsg = res.success
          ? 'Ready (${rmWatch.elapsedMilliseconds} ms · ${res.candleCount} bars)'
          : 'Failed (${rmWatch.elapsedMilliseconds} ms · ${res.message})';
    } catch (e) {
      rmWatch.stop();
      rmMsg = 'Failed (${rmWatch.elapsedMilliseconds} ms · $e)';
    }

    // 3. LLM Inference Ping
    final aiWatch = Stopwatch()..start();
    bool aiOk = false;
    String aiMsg = '';
    try {
      final isConnected = await _aiService.testConnection().timeout(
        const Duration(seconds: 5),
      );
      aiWatch.stop();
      aiOk = isConnected;
      final modelName = AppRemoteConfig.instance.llmModel;
      aiMsg = isConnected
          ? '$modelName (${aiWatch.elapsedMilliseconds} ms · Active)'
          : 'Failed (${aiWatch.elapsedMilliseconds} ms · Unresponsive)';
    } catch (e) {
      aiWatch.stop();
      aiMsg = 'Failed (${aiWatch.elapsedMilliseconds} ms · $e)';
    }

    // 4. Native Daemon & Permissions Status
    bool daemonOk = false;
    var batteryOk = false;
    var dndOk = false;
    var overlayOk = false;
    String daemonMsg = '';
    try {
      final telemetry = await _alarmService.getSystemTelemetry();
      final isRunning = telemetry['daemonRunning'] as bool? ?? false;
      batteryOk = telemetry['batteryIgnored'] as bool? ?? false;
      dndOk = telemetry['dndGranted'] as bool? ?? false;
      overlayOk = telemetry['overlayGranted'] as bool? ?? false;
      final pid = telemetry['pid'];
      daemonOk = isRunning;
      daemonMsg = isRunning
          ? 'Running${pid == null ? '' : ' (PID $pid)'}'
          : 'Not running or status unavailable';
    } catch (e) {
      daemonMsg = 'Error: $e';
    }

    if (!mounted) return;
    Navigator.pop(context);

    final allHealthy =
        biquoteOk &&
        rmOk &&
        aiOk &&
        daemonOk &&
        batteryOk &&
        dndOk &&
        overlayOk;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: Row(
          children: [
            Icon(
              allHealthy ? Icons.verified_rounded : Icons.warning_amber_rounded,
              color: allHealthy
                  ? const Color(0xFF43E06A)
                  : const Color(0xFFFF9F0A),
            ),
            const SizedBox(width: 8),
            Text(
              allHealthy ? 'All Systems Healthy' : 'Diagnostics Warning',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDiagnosticResultRow('Biquote Feed', biquoteMsg, biquoteOk),
            const SizedBox(height: 8),
            _buildDiagnosticResultRow('Candle API', rmMsg, rmOk),
            const SizedBox(height: 8),
            _buildDiagnosticResultRow('LLM Inference', aiMsg, aiOk),
            const SizedBox(height: 8),
            _buildDiagnosticResultRow('Background Daemon', daemonMsg, daemonOk),
            Text(
              'Battery optimization: ${batteryOk ? "Exempt" : "Not exempt"} · DND: ${dndOk ? "Granted" : "Restricted"} · Overlay: ${overlayOk ? "Active" : "Disabled"}',
              style: const TextStyle(color: Color(0x8EEBEBF5), fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              final log =
                  '''TenX Live Diagnostic Results:
- Biquote Feed: $biquoteMsg
- Candle API: $rmMsg
- LLM Inference: $aiMsg
- Foreground Daemon: $daemonMsg
- Battery Optimization: ${batteryOk ? "Exempt" : "Not exempt"}
- DND Override: ${dndOk ? "Granted" : "Restricted"}
- System Overlay: ${overlayOk ? "Active" : "Disabled"}''';
              Clipboard.setData(ClipboardData(text: log));
              Navigator.pop(ctx);
              TenXToast.show(
                context,
                title: 'Report Copied',
                subtitle: 'Live diagnostic report copied to clipboard.',
              );
            },
            child: const Text(
              'Copy Log',
              style: TextStyle(color: Color(0xFF0A84FF)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2C2C2E),
            ),
            child: const Text('Done', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticResultRow(String label, String message, bool isOk) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isOk ? Icons.check_circle_rounded : Icons.error_outline_rounded,
          size: 16,
          color: isOk ? const Color(0xFF43E06A) : const Color(0xFFFF453A),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                message,
                style: TextStyle(
                  color: isOk
                      ? const Color(0xFF43E06A)
                      : const Color(0xFFFF9F0A),
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _exportBackupJson() async {
    final includeSecrets =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xFF1C1C1E),
            title: const Text(
              'Save Unencrypted Backup?',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'This backup contains your API credentials and other settings as readable, unencrypted JSON. Anyone who can access the saved file can read those credentials. Save it only to a trusted location.',
              style: TextStyle(color: Color(0xFFEBEBF5)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Continue'),
              ),
            ],
          ),
        ) ??
        false;
    if (!includeSecrets || !mounted) return;
    final jsonStr = const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'settings': SettingsProvider().exportSettingsToJson(),
      'alerts':
          widget.alertManager?.exportBackupData() ??
          {
            'alerts': <Map<String, dynamic>>[],
            'history': <Map<String, dynamic>>[],
          },
      'aiData': await _storage.exportBackupData(),
    });
    if (!mounted) return;
    final saved = await _saveExportFile(
      'tenx_backup_${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}.json',
      'application/json',
      jsonStr,
    );
    if (!mounted) return;
    TenXToast.show(
      context,
      title: saved ? 'Backup Saved' : 'Export Cancelled',
      subtitle: saved
          ? 'Backup saved to the location you selected.'
          : 'Choose a location to save the backup.',
    );
  }

  Future<bool> _saveExportFile(
    String filename,
    String mimeType,
    String content,
  ) async {
    try {
      return await const MethodChannel('com.example.alert_app/alarm')
              .invokeMethod<bool>('saveExportFile', {
                'filename': filename,
                'mimeType': mimeType,
                'content': content,
              }) ??
          false;
    } on PlatformException catch (error) {
      if (mounted) {
        TenXToast.show(
          context,
          title: 'Export Failed',
          subtitle: error.message ?? 'Could not save the export.',
        );
      }
      return false;
    }
  }

  void _showRestoreBackupDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text(
          'Restore Backup',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste your exported settings JSON below:',
              style: TextStyle(color: Color(0x9EEBEBF5), fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 6,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Colors.white,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF2C2C2E),
                hintText: '{\n  "soundTitle": "System default",\n  ...\n}',
                hintStyle: const TextStyle(color: Color(0x56EBEBF5)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                if (data?.text != null) {
                  controller.text = data!.text!;
                }
              },
              icon: const Icon(
                Icons.paste_rounded,
                size: 16,
                color: Color(0xFF0A84FF),
              ),
              label: const Text(
                'Paste from Clipboard',
                style: TextStyle(color: Color(0xFF0A84FF), fontSize: 13),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () async {
              var applyingRestore = false;
              try {
                final text = controller.text.trim();
                if (text.isEmpty) return;
                final Map<String, dynamic> map = jsonDecode(text);
                final settings = map['schemaVersion'] != null
                    ? Map<String, dynamic>.from(map['settings'] as Map)
                    : map;
                final aiData = map['aiData'] == null
                    ? null
                    : Map<String, dynamic>.from(map['aiData'] as Map);
                final alertData = map['alerts'] == null
                    ? null
                    : Map<String, dynamic>.from(map['alerts'] as Map);
                // Parse and validate every section before changing any persisted state.
                SettingsProvider.validateSettingsImport(settings);
                if (aiData != null) StrategyStorage.validateBackupData(aiData);
                if (alertData != null) {
                  AlertManager.validateBackupData(alertData);
                }
                if (map['schemaVersion'] != null &&
                    (map['schemaVersion'] != 1 || map['settings'] is! Map)) {
                  throw const FormatException('Unsupported backup format');
                }
                final previousSettings = SettingsProvider()
                    .exportSettingsToJson();
                final previousAiData = await _storage.exportBackupData();
                final previousAlertData = widget.alertManager
                    ?.exportBackupData();
                applyingRestore = true;
                if (map['schemaVersion'] != null) {
                  try {
                    await StorageService.withStrictWrites(() async {
                      await SettingsProvider().importSettingsFromJson(settings);
                      if (aiData != null) {
                        await _storage.importBackupData(
                          aiData,
                          strictPersistence: true,
                        );
                      }
                      if (alertData != null && widget.alertManager != null) {
                        await widget.alertManager!.importBackupData(
                          alertData,
                          strictPersistence: true,
                        );
                      }
                    });
                  } catch (applyError) {
                    try {
                      await StorageService.withStrictWrites(() async {
                        await SettingsProvider().importSettingsFromJson(
                          previousSettings,
                        );
                        await _storage.importBackupData(
                          previousAiData,
                          strictPersistence: true,
                        );
                        if (previousAlertData != null &&
                            widget.alertManager != null) {
                          await widget.alertManager!.importBackupData(
                            previousAlertData,
                            strictPersistence: true,
                          );
                        }
                      });
                    } catch (rollbackError) {
                      throw StateError(
                        'Restore write failed ($applyError) and rollback failed ($rollbackError)',
                      );
                    }
                    throw StateError(
                      'Restore write failed; previous data was restored: $applyError',
                    );
                  }
                } else {
                  // Continue to accept pre-envelope settings-only exports.
                  try {
                    await StorageService.withStrictWrites(
                      () => SettingsProvider().importSettingsFromJson(settings),
                    );
                  } catch (applyError) {
                    try {
                      await StorageService.withStrictWrites(
                        () => SettingsProvider().importSettingsFromJson(
                          previousSettings,
                        ),
                      );
                    } catch (rollbackError) {
                      throw StateError(
                        'Restore write failed ($applyError) and rollback failed ($rollbackError)',
                      );
                    }
                    throw StateError(
                      'Restore write failed; previous settings were restored: $applyError',
                    );
                  }
                }
                await _loadAllSettings();
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  TenXToast.show(
                    context,
                    title: 'Backup Restored',
                    subtitle: 'All settings updated successfully.',
                  );
                }
              } catch (error) {
                if (mounted) {
                  TenXToast.show(
                    context,
                    title: 'Restore Failed',
                    subtitle: applyingRestore
                        ? error.toString().contains('rollback failed')
                              ? 'A storage write and rollback both failed. Some stored values may need manual recovery.'
                              : 'Could not persist the restored data. The previous data was restored.'
                        : 'The backup JSON or its fields are invalid: $error',
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF30D158),
            ),
            child: const Text(
              'Restore',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportTradingJournalCsv() async {
    final history = widget.alertManager?.history ?? [];
    final recentRuns = await _storage.getPersistedRecentRuns();
    final StringBuffer csv = StringBuffer();
    String cell(Object? value) => '"${value.toString().replaceAll('"', '""')}"';
    csv.writeln(
      'Date,RecordType,Symbol,StrategyOrCondition,TargetOrScore,PriceOrDirection,NoteOrSpecialistVotes',
    );
    for (final alert in history) {
      csv.writeln(
        [
          cell(
            alert.triggeredAt?.toIso8601String() ??
                alert.createdAt.toIso8601String(),
          ),
          cell('Alert'),
          cell(alert.symbol),
          cell(alert.condition.label),
          cell(alert.targetPrice),
          cell(alert.initialPrice),
          cell(alert.note.isNotEmpty ? alert.note : 'Fired'),
        ].join(','),
      );
    }
    for (final run in recentRuns) {
      final votes = run.specialistSignals
          .map(
            (signal) =>
                '${signal.agentName}: ${signal.direction.label} (${signal.confidence}%)',
          )
          .join(' | ');
      csv.writeln(
        [
          cell(run.timestamp.toIso8601String()),
          cell('AI Signal'),
          cell(run.symbol),
          cell(run.strategyOrAgentName),
          cell(run.score),
          cell(run.signal.direction.label),
          cell(votes),
        ].join(','),
      );
    }
    final saved = await _saveExportFile(
      'tenx_trading_journal_${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}.csv',
      'text/csv',
      csv.toString(),
    );
    if (!mounted) return;
    TenXToast.show(
      context,
      title: saved ? 'Journal Saved' : 'Export Cancelled',
      subtitle: saved
          ? 'CSV saved to the location you selected.'
          : 'Choose a location to save the journal.',
    );
  }

  Future<void> _showDiagnosticsTerminalModal() async {
    final telemetry = await _alarmService.getSystemTelemetry();
    final cacheStats = await RealMarketService.getCachedCandleStats();
    if (!mounted) return;

    final os = telemetry['os'] ?? 'Unavailable';
    final abi = telemetry['abi'] ?? 'Unavailable';
    final model = telemetry['model'] ?? 'Unavailable';
    final pid = telemetry['pid'];
    final daemonRunning = telemetry['daemonRunning'] as bool?;
    final dnd = telemetry['dndGranted'] as bool? ?? _dndGranted;
    final battery = telemetry['batteryIgnored'] as bool? ?? _batteryIgnored;
    final overlay = telemetry['overlayGranted'] as bool? ?? _overlayGranted;
    final memUsed = telemetry['memoryUsedMb'];
    final memMax = telemetry['memoryMaxMb'];
    final cachedBars = cacheStats.candleCount;
    final isSocketConnected = widget.biquoteService?.isConnected ?? false;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.terminal_rounded, color: Color(0xFF64D2FF)),
                SizedBox(width: 8),
                Text(
                  'Device & Daemon Telemetry',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Hardware, background service, and daemon status.',
              style: TextStyle(fontSize: 13, color: Color(0x9EEBEBF5)),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF141416),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x17FFFFFF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'HARDWARE: $model · $abi',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'OS: $os',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Color(0xFF43E06A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'DAEMON: ${daemonRunning == null
                        ? "UNKNOWN"
                        : daemonRunning
                        ? "ACTIVE"
                        : "SUSPENDED"}${pid == null ? "" : " (PID $pid)"}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: daemonRunning == true
                          ? const Color(0xFF43E06A)
                          : const Color(0xFFFF453A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'RAM USAGE: ${memUsed == null ? "Unavailable" : "$memUsed MB"} / ${memMax == null ? "Unavailable" : "$memMax MB"}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'DND OVERRIDE: ${dnd ? "GRANTED" : "RESTRICTED"}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: dnd
                          ? const Color(0xFF43E06A)
                          : const Color(0xFFFF9F0A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'APP OVERLAY: ${overlay ? "GRANTED" : "DISABLED"}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: overlay
                          ? const Color(0xFF43E06A)
                          : const Color(0xFFFF9F0A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'BATTERY OPT: ${battery ? "WHITELISTED" : "RESTRICTED"}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: battery
                          ? const Color(0xFF43E06A)
                          : const Color(0xFFFF9F0A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'SOCKET: ${isSocketConnected ? "CONNECTED" : "STANDBY"} ($_biquoteLatency)',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'CACHED CANDLES: $cachedBars bars stored locally${cacheStats.unreadableEntries > 0 ? ' · ${cacheStats.unreadableEntries} unreadable entries' : ''}${cacheStats.missingEntries > 0 ? ' · ${cacheStats.missingEntries} missing entries' : ''}${cacheStats.indexReadable ? '' : ' · index unreadable'}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ACTIVE ALERTS: ${widget.alertManager?.activeAlerts.length ?? 0}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Color(0x9EEBEBF5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await _shareSanitizedReport(telemetry: telemetry);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('Share Sanitized Log'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0A84FF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareSanitizedReport({Map<String, dynamic>? telemetry}) async {
    final t = telemetry ?? await _alarmService.getSystemTelemetry();
    final cacheStats = await RealMarketService.getCachedCandleStats();
    final os = t['os'] ?? 'Unavailable';
    final model = t['model'] ?? 'Unavailable';
    final pid = t['pid'];
    final isRunning = t['daemonRunning'] as bool?;
    final dnd = t['dndGranted'] as bool? ?? _dndGranted;
    final battery = t['batteryIgnored'] as bool? ?? _batteryIgnored;
    final overlay = t['overlayGranted'] as bool? ?? _overlayGranted;
    final cachedBars = cacheStats.candleCount;

    final report =
        '''TenX Financial Terminal Diagnostics Report
Timestamp: ${DateTime.now().toUtc().toIso8601String()}
Hardware: $model
Platform: $os
Foreground Daemon: ${isRunning == null
            ? "Unknown"
            : isRunning
            ? "Active"
            : "Suspended"}${pid == null ? "" : " (PID $pid)"}
Battery Optimization: ${battery ? "Whitelisted" : "Standard"}
DND Override: ${dnd ? "Granted" : "Restricted"}
System Overlay: ${overlay ? "Granted" : "Disabled"}
Offline Candle Cache: $cachedBars bars retained${cacheStats.unreadableEntries > 0 ? ' · ${cacheStats.unreadableEntries} unreadable entries' : ''}${cacheStats.missingEntries > 0 ? ' · ${cacheStats.missingEntries} missing entries' : ''}${cacheStats.indexReadable ? '' : ' · index unreadable'}
Market Data: Biquote Stream ($_biquoteLatency)
Candles Feed: App-wide provider (${ApiConfig.realMarketBaseUrl})
LLM Model: ${AppRemoteConfig.instance.llmModel}
API Key: ***REDACTED***
Active Alerts: ${widget.alertManager?.activeAlerts.length ?? 0}
Fired History: ${widget.alertManager?.history.length ?? 0}
Sessions Monitored: ${_selectedSessions.join(", ")}
Status: Not evaluated by this telemetry report.''';

    try {
      await _alarmService.shareText(report);
    } catch (e) {
      if (!mounted) return;
      TenXToast.show(context, title: 'Share failed', subtitle: '$e');
      return;
    }
    if (!mounted) return;
    TenXToast.show(
      context,
      title: 'Share sheet opened',
      subtitle: 'Diagnostic report is sanitized; API keys are redacted.',
    );
  }

  void _confirmFactoryReset() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text(
          'Reset to Defaults?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This resets app preferences and removes custom sound uploads. Your alerts, alert history, cached candles, AI strategies, and API connection settings will be kept.',
          style: TextStyle(color: Color(0x9EEBEBF5)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final customTones = await _alarmService.getCustomAudios();
              for (final tone in customTones) {
                await _alarmService.deleteCustomAudio(tone.uri);
              }
              await SettingsProvider().resetToDefaults();
              await _loadAllSettings();
              if (!mounted) return;
              TenXToast.show(
                context,
                title: 'Factory Reset Complete',
                subtitle: 'All settings returned to defaults.',
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF453A),
            ),
            child: const Text(
              'Reset All',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // Visual Building Blocks (Matching Settings.dc.html)
  // ==========================================
  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 18, 32, 7),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.09 * 11,
          color: Color(0x9EEBEBF5),
        ),
      ),
    );
  }

  Widget _buildCardGroup(List<Widget> children) {
    final groups = <({String? title, List<Widget> rows})>[];
    String? currentTitle;
    var currentRows = <Widget>[];
    for (final child in children) {
      if (child is _SettingsSubgroup) {
        if (currentRows.isNotEmpty) {
          groups.add((title: currentTitle, rows: currentRows));
        }
        currentTitle = child.title;
        currentRows = <Widget>[];
      } else {
        currentRows.add(child);
      }
    }
    if (currentRows.isNotEmpty) {
      groups.add((title: currentTitle, rows: currentRows));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in groups) ...[
          if (group.title != null) _buildSectionLabel(group.title!),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: group.rows),
          ),
        ],
      ],
    );
  }

  Widget _buildRowItem({
    required Widget icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    bool showDivider = true,
  }) {
    return KeyedSubtree(
      key: _settingRowKeys.putIfAbsent(title, GlobalKey.new),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    icon,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                              color: Colors.white,
                              letterSpacing: -0.2,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0x8EEBEBF5),
                                letterSpacing: -0.1,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      trailing,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconBadge(Color bgColor, IconData icon) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Center(child: Icon(icon, color: Colors.white, size: 18)),
    );
  }

  Widget _buildSwitch({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return CupertinoSwitch(
      value: value,
      activeTrackColor: const Color(0xFF30D158),
      onChanged: onChanged,
    );
  }

  Widget _buildTrailingTextWithChevron(String text, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 15,
            color: color ?? const Color(0x9EEBEBF5),
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(width: 4),
        const Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: Color(0x56EBEBF5),
        ),
      ],
    );
  }

  String _categoryDisplayName(String section) =>
      _categories.firstWhere((category) => category.section == section).title;

  void _openSettingsCategory(String section, {String? target}) {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => SettingsScreen(
          isDark: widget.isDark,
          onToggleTheme: widget.onToggleTheme,
          alertManager: widget.alertManager,
          biquoteService: widget.biquoteService,
          initialCategory: section,
          initialSearchTarget: target,
        ),
      ),
    );
  }

  bool _matchesSettingsQuery(_SettingsSearchItem item, String query) {
    final category = _categories.firstWhere(
      (entry) => entry.section == item.category,
    );
    final searchableText = [
      item.title,
      item.description,
      item.category,
      category.title,
      category.subtitle,
    ].join(' ').toLowerCase();
    final terms = query.split(RegExp(r'\s+')).where((term) => term.isNotEmpty);
    return terms.every((term) => searchableText.contains(term));
  }

  List<Widget> _buildCategoryIndex() {
    final query = _settingsSearchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      final matches = _searchItems
          .where((item) => _matchesSettingsQuery(item, query))
          .toList();
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: CupertinoSearchTextField(
            controller: _settingsSearchController,
            autofocus: true,
            placeholder: 'Search settings and descriptions',
            style: const TextStyle(color: Colors.white, fontSize: 16),
            placeholderStyle: const TextStyle(color: Color(0xFF8E8E93)),
            backgroundColor: const Color(0xFF1C1C1E),
            itemColor: const Color(0xFF8E8E93),
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (matches.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 28, 24, 18),
            child: Center(
              child: Text(
                'No matching settings',
                style: TextStyle(color: Color(0xFF8E8E93)),
              ),
            ),
          )
        else ...[
          _buildSectionLabel('RESULTS'),
          _buildCardGroup([
            for (final item in matches)
              _buildRowItem(
                icon: _buildIconBadge(
                  const Color(0xFF0A84FF),
                  Icons.tune_rounded,
                ),
                title: item.title,
                subtitle: item.description.isEmpty
                    ? _categoryDisplayName(item.category)
                    : '${_categoryDisplayName(item.category)} · ${item.description}',
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF8E8E93),
                ),
                onTap: () =>
                    _openSettingsCategory(item.category, target: item.title),
              ),
          ]),
        ],
      ];
    }

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: CupertinoSearchTextField(
          controller: _settingsSearchController,
          placeholder: 'Search settings and descriptions',
          style: const TextStyle(color: Colors.white, fontSize: 16),
          placeholderStyle: const TextStyle(color: Color(0xFF8E8E93)),
          backgroundColor: const Color(0xFF1C1C1E),
          itemColor: const Color(0xFF8E8E93),
          onChanged: (_) => setState(() {}),
        ),
      ),
      _buildSectionLabel('SETTINGS'),
      _buildCardGroup([
        if (widget.onManageAccount != null)
          _buildRowItem(
            icon: _buildIconBadge(
              const Color(0xFF64D2FF),
              Icons.account_circle_rounded,
            ),
            title: 'TenX account',
            subtitle: 'Manage sign-in, account details and deletion',
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF8E8E93),
            ),
            onTap: widget.onManageAccount,
          ),
        for (final category in _categories)
          _buildRowItem(
            icon: _buildIconBadge(const Color(0xFF0A84FF), category.icon),
            title: category.title,
            subtitle: category.subtitle,
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF8E8E93),
            ),
            onTap: () => _openSettingsCategory(category.section),
          ),
      ]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: true,
        bottom: false,
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF0A84FF)),
              )
            : Column(
                children: [
                  // Sticky Header Title
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    decoration: const BoxDecoration(color: Colors.black),
                    child: Row(
                      children: [
                        if (widget.initialCategory != null)
                          IconButton(
                            tooltip: 'Back to Settings',
                            onPressed: () => Navigator.maybePop(context),
                            icon: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 20,
                              color: Color(0xFF0A84FF),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            widget.initialCategory == null
                                ? 'Settings'
                                : _categoryDisplayName(widget.initialCategory!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: widget.initialCategory == null
                                  ? 34
                                  : 27,
                              fontWeight: FontWeight.w700,
                              letterSpacing: widget.initialCategory == null
                                  ? -0.03 * 34
                                  : -0.02 * 27,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async {
                        await _loadAllSettings();
                        await _measureBiquoteLatency();
                      },
                      child: ListView(
                        padding: const EdgeInsets.only(top: 8, bottom: 120),
                        children: [
                          if (widget.initialCategory == null)
                            ..._buildCategoryIndex(),
                          // ==========================================
                          // 1. MARKET DATA
                          // ==========================================
                          if (widget.initialCategory == 'MARKET DATA')
                            _buildCardGroup([
                              const _SettingsSubgroup('FEED & CONNECTION'),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF30D158),
                                  Icons.wifi_rounded,
                                ),
                                title: 'Biquote feed',
                                trailing: Text(
                                  _biquoteLatency,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF8E8E93),
                                  ),
                                ),
                                onTap: () {
                                  _measureBiquoteLatency();
                                  TenXToast.show(
                                    context,
                                    title: 'Biquote Ping Tested',
                                    subtitle: _biquoteLatency,
                                  );
                                },
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF0A84FF),
                                  Icons.sync_rounded,
                                ),
                                title: 'Automatic reconnect',
                                subtitle: 'Resubscribe WebSocket channels upon reconnection',
                                trailing: _buildSwitch(
                                  value: _biquoteAutoReconnect,
                                  onChanged: (v) {
                                    setState(() => _biquoteAutoReconnect = v);
                                    SettingsProvider().setBiquoteAutoReconnect(
                                      v,
                                    );
                                    widget.biquoteService
                                        ?.applyReconnectSettings();
                                  },
                                ),
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF5E5CE6),
                                  Icons.swap_vert_rounded,
                                ),
                                title: 'Direct IP fallback',
                                subtitle: 'Retry Biquote over its fixed IP when domain DNS fails',
                                trailing: _buildSwitch(
                                  value: _directIpFallback,
                                  onChanged: (v) {
                                    setState(() => _directIpFallback = v);
                                    SettingsProvider().setDirectIpFallback(v);
                                  },
                                ),
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF5E5CE6),
                                  Icons.swap_vert_rounded,
                                ),
                                title: 'REST quote fallback',
                                subtitle: 'Poll Biquote quotes once per second while SignalR is unavailable',
                                trailing: _buildSwitch(
                                  value: _transportFallback,
                                  onChanged: (v) {
                                    setState(() => _transportFallback = v);
                                    SettingsProvider().setTransportFallback(v);
                                  },
                                ),
                              ),
                              const _SettingsSubgroup('HISTORICAL DATA'),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFFFF9F0A),
                                  Icons.candlestick_chart_rounded,
                                ),
                                title: 'Historical candles provider',
                                subtitle: 'App-wide provider configuration',
                                trailing: const Text(
                                  'Managed',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Color(0x9EEBEBF5),
                                  ),
                                ),
                              ),
                              const _SettingsSubgroup('TIMEZONE & DISPLAY'),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF64D2FF),
                                  Icons.public_rounded,
                                ),
                                title: 'Global trading timezone',
                                trailing: _buildTrailingTextWithChevron(
                                  _tradingTimezone,
                                ),
                                onTap: () {
                                  final zones = [
                                    'UTC / GMT',
                                    'Local Device Time',
                                    'New York (EST/EDT)',
                                    'London (GMT/BST)',
                                    'Tokyo (JST)',
                                  ];
                                  showModalBottomSheet(
                                    context: context,
                                    backgroundColor: const Color(0xFF1C1C1E),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(22),
                                      ),
                                    ),
                                    builder: (ctx) => Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Global Trading Timezone',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          ...zones.map(
                                            (z) => ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              title: Text(
                                                z,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                              trailing: _tradingTimezone == z
                                                  ? const Icon(
                                                      Icons.check_rounded,
                                                      color: Color(0xFF0A84FF),
                                                    )
                                                  : null,
                                              onTap: () {
                                                setState(
                                                  () => _tradingTimezone = z,
                                                );
                                                SettingsProvider()
                                                    .setTradingTimezone(z);
                                                Navigator.pop(ctx);
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF34C759),
                                  Icons.compare_arrows_rounded,
                                ),
                                title: 'Live feed spread display',
                                subtitle: 'Show Biquote bid/ask spread on the chart. Broker slippage is not available.',
                                trailing: _buildSwitch(
                                  value: _showSpreadDisplay,
                                  onChanged: (v) {
                                    setState(() => _showSpreadDisplay = v);
                                    SettingsProvider().setShowSpreadDisplay(v);
                                  },
                                ),
                              ),
                              const _SettingsSubgroup('SESSION ALERTS'),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFFFF9F0A),
                                  Icons.alarm_on_rounded,
                                ),
                                title: 'Session open alerts',
                                subtitle: 'Notify when London, New York, or Asian markets open',
                                trailing: _buildTrailingTextWithChevron(
                                  '${_selectedSessions.length} active',
                                ),
                                onTap: _showSessionAlertsPicker,
                                showDivider: false,
                              ),
                            ]),

                          // ==========================================
                          // 2. BACKGROUND MONITORING
                          // ==========================================
                          if (widget.initialCategory == 'BACKGROUND MONITORING')
                            _buildCardGroup([
                              const _SettingsSubgroup('MONITOR SERVICE'),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFFBF5AF2),
                                  Icons.access_time_rounded,
                                ),
                                title: 'Perpetual monitoring service',
                                subtitle: 'Keep alerts active when app is closed or device is locked',
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _perpetualServiceRunning
                                          ? 'Running'
                                          : (_perpetualServiceActive
                                                ? 'Starting'
                                                : 'Paused'),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _perpetualServiceRunning
                                            ? const Color(0xFF43E06A)
                                            : const Color(0xFFFF453A),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    _buildSwitch(
                                      value: _perpetualServiceActive,
                                      onChanged: (v) async {
                                        setState(
                                          () => _perpetualServiceActive = v,
                                        );
                                        SettingsProvider()
                                            .setPerpetualServiceActive(v);
                                        if (v) {
                                          await _alarmService
                                              .startForegroundService();
                                          await _refreshMonitoringStatus(
                                            waitForStart: true,
                                          );
                                          if (mounted) {
                                            TenXToast.show(
                                              this.context,
                                              title: _perpetualServiceRunning
                                                  ? 'Monitoring Active'
                                                  : 'Monitoring unavailable',
                                              subtitle: _perpetualServiceRunning
                                                  ? 'Foreground service daemon running'
                                                  : 'Android did not start the monitoring service',
                                            );
                                          }
                                        } else {
                                          await _alarmService
                                              .stopForegroundService();
                                          await _refreshMonitoringStatus();
                                          if (mounted) {
                                            TenXToast.show(
                                              this.context,
                                              title: 'Monitoring Paused',
                                              subtitle:
                                                  'Background alerts suspended',
                                            );
                                          }
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const _SettingsSubgroup('PERMISSIONS'),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFFFF9F0A),
                                  Icons.battery_charging_full_rounded,
                                ),
                                title: 'Battery optimization',
                                subtitle: 'Prevent Android from putting background monitoring to sleep',
                                trailing: _buildTrailingTextWithChevron(
                                  _batteryIgnored
                                      ? 'Unrestricted'
                                      : 'Action needed',
                                  color: _batteryIgnored
                                      ? const Color(0xFF43E06A)
                                      : const Color(0xFFFF9F0A),
                                ),
                                onTap: () async {
                                  await _alarmService
                                      .requestIgnoreBatteryOptimizations();
                                  final res = await _alarmService
                                      .isBatteryOptimizationIgnored();
                                  setState(() => _batteryIgnored = res);
                                },
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFFFF453A),
                                  Icons.do_not_disturb_on_rounded,
                                ),
                                title: 'Bypass Do Not Disturb',
                                subtitle: 'Allow critical price alarms to sound on silent',
                                trailing: _buildTrailingTextWithChevron(
                                  _dndGranted ? 'Allowed' : 'Action needed',
                                  color: _dndGranted
                                      ? const Color(0xFF43E06A)
                                      : const Color(0xFFFF9F0A),
                                ),
                                onTap: () async {
                                  await _alarmService.requestDndOverride();
                                  final res = await _alarmService
                                      .isDndOverrideGranted();
                                  setState(() => _dndGranted = res);
                                },
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF32D74B),
                                  Icons.screen_lock_portrait_rounded,
                                ),
                                title: 'Full-screen lock-screen access',
                                subtitle: 'Android permission for alert screens over the lock screen',
                                trailing: _buildTrailingTextWithChevron(
                                  _fullScreenIntentAllowed
                                      ? 'Allowed'
                                      : 'Grant',
                                  color: _fullScreenIntentAllowed
                                      ? const Color(0xFF43E06A)
                                      : const Color(0xFFFF9F0A),
                                ),
                                onTap: () async {
                                  await _alarmService
                                      .requestFullScreenIntentPermission();
                                  await _refreshSystemPermissions();
                                },
                              ),
                              const _SettingsSubgroup('MONITORING BEHAVIOR'),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF30D158),
                                  Icons.speed_rounded,
                                ),
                                title: 'Polling frequency',
                                trailing: _buildTrailingTextWithChevron(
                                  _pollingRate,
                                ),
                                onTap: () {
                                  final rates = [
                                    'Ultra Fast (2s)',
                                    'Standard (5s)',
                                    'Eco Battery Saver (15s)',
                                  ];
                                  showModalBottomSheet(
                                    context: context,
                                    backgroundColor: const Color(0xFF1C1C1E),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(22),
                                      ),
                                    ),
                                    builder: (ctx) => Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Polling Frequency',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          ...rates.map(
                                            (r) => ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              title: Text(
                                                r,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              trailing: _pollingRate == r
                                                  ? const Icon(
                                                      Icons.check_rounded,
                                                      color: Color(0xFF0A84FF),
                                                    )
                                                  : null,
                                              onTap: () {
                                                setState(
                                                  () => _pollingRate = r,
                                                );
                                                SettingsProvider()
                                                    .setPollingRate(r);
                                                Navigator.pop(ctx);
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF64D2FF),
                                  Icons.mobile_friendly_rounded,
                                ),
                                title: 'Wake screen on alert',
                                trailing: _buildSwitch(
                                  value: _screenWakeup,
                                  onChanged: (v) {
                                    setState(() => _screenWakeup = v);
                                    SettingsProvider().setScreenWakeup(v);
                                  },
                                ),
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF007AFF),
                                  Icons.notification_important_rounded,
                                ),
                                title: 'Persistent price notification',
                                subtitle: 'Show a live quote in Android notifications while monitoring',
                                trailing: _buildSwitch(
                                  value: _statusBarTicker,
                                  onChanged: (v) {
                                    setState(() => _statusBarTicker = v);
                                    SettingsProvider().setStatusBarTicker(v);
                                  },
                                ),
                              ),
                              const _SettingsSubgroup('NETWORK & BATTERY'),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFFFF9F0A),
                                  Icons.wifi_off_rounded,
                                ),
                                title: 'Connection loss warning',
                                subtitle: 'Sound alarm if internet drops for over 3 minutes',
                                trailing: _buildSwitch(
                                  value: _deadManWarning,
                                  onChanged: (v) {
                                    setState(() => _deadManWarning = v);
                                    SettingsProvider().setDeadManWarning(v);
                                  },
                                ),
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF34C759),
                                  Icons.swap_horiz_rounded,
                                ),
                                title: 'Automatic network failover',
                                subtitle: 'Retry the market socket faster after a network drop',
                                trailing: _buildSwitch(
                                  value: _autoNetworkFailover,
                                  onChanged: (v) {
                                    setState(() => _autoNetworkFailover = v);
                                    SettingsProvider().setAutoNetworkFailover(
                                      v,
                                    );
                                    widget.biquoteService
                                        ?.applyReconnectSettings();
                                  },
                                ),
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFFFF453A),
                                  Icons.battery_alert_rounded,
                                ),
                                title: 'Low battery alert protection',
                                subtitle: 'Notify at 15% or below and reduce market checks to every 15 seconds',
                                trailing: _buildSwitch(
                                  value: _lowBatteryGuard,
                                  onChanged: (v) {
                                    setState(() => _lowBatteryGuard = v);
                                    SettingsProvider().setLowBatteryGuard(v);
                                  },
                                ),
                                showDivider: false,
                              ),
                            ]),

                          // ==========================================
                          // 3. ALARMS & AUDIO
                          // ==========================================
                          if (widget.initialCategory == 'ALARMS & AUDIO')
                            _buildCardGroup([
                              const _SettingsSubgroup('SOUND'),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF0A84FF),
                                  Icons.music_note_rounded,
                                ),
                                title: 'Alarm ringtone',
                                subtitle:
                                    'Tap to preview or select global tone',
                                trailing: _buildTrailingTextWithChevron(
                                  _selectedSoundTitle,
                                ),
                                onTap: _showSoundPickerSheet,
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFFBF5AF2),
                                  Icons.folder_special_rounded,
                                ),
                                title: 'Uploaded audio library',
                                subtitle: 'Manage user imported sound clips',
                                trailing: _buildTrailingTextWithChevron(
                                  'Manage',
                                ),
                                onTap: _showSoundPickerSheet,
                              ),
                              // Volume Slider Row
                              Column(
                                children: [
                                  Container(
                                    constraints: const BoxConstraints(
                                      minHeight: 48,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      children: [
                                        _buildIconBadge(
                                          const Color(0xFF8E8E93),
                                          Icons.volume_up_rounded,
                                        ),
                                        const SizedBox(width: 12),
                                        const Text(
                                          'Alarm volume',
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: Colors.white,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: SliderTheme(
                                            data: SliderTheme.of(context)
                                                .copyWith(
                                                  activeTrackColor:
                                                      Colors.white,
                                                  inactiveTrackColor:
                                                      const Color(0xFF3A3A3C),
                                                  thumbColor: Colors.white,
                                                  trackHeight: 3,
                                                  thumbShape:
                                                      const RoundSliderThumbShape(
                                                        enabledThumbRadius: 6,
                                                      ),
                                                  overlayShape:
                                                      SliderComponentShape
                                                          .noOverlay,
                                                ),
                                            child: Slider(
                                              value: _alarmVolume,
                                              onChanged: (val) {
                                                setState(
                                                  () => _alarmVolume = val,
                                                );
                                                SettingsProvider()
                                                    .setAlarmVolume(val);
                                              },
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${(_alarmVolume * 100).toInt()}%',
                                          style: const TextStyle(
                                            color: Color(0x9EEBEBF5),
                                            fontSize: 13,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFFFF453A),
                                  Icons.campaign_rounded,
                                ),
                                title: 'Force maximum volume',
                                subtitle: 'Sound at full volume regardless of system slider',
                                trailing: _buildSwitch(
                                  value: _forceMaxVolume,
                                  onChanged: (v) {
                                    setState(() => _forceMaxVolume = v);
                                    SettingsProvider().setForceMaxVolume(v);
                                  },
                                ),
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF30D158),
                                  Icons.trending_up_rounded,
                                ),
                                title: 'Gradual volume escalation',
                                subtitle: 'Starts at 30% and reaches the selected alarm volume in 5 seconds',
                                trailing: _buildSwitch(
                                  value: _volumeEscalation,
                                  onChanged: (v) {
                                    setState(() => _volumeEscalation = v);
                                    SettingsProvider().setVolumeEscalation(v);
                                  },
                                ),
                              ),
                              const _SettingsSubgroup(
                                'QUIET HOURS & VIBRATION',
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF5E5CE6),
                                  Icons.bedtime_rounded,
                                ),
                                title: 'Quiet hours',
                                trailing: _buildTrailingTextWithChevron(
                                  _quietHoursEnabled ? _quietHours : 'Off',
                                ),
                                onTap: _showQuietHoursSheet,
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFFFF9F0A),
                                  Icons.vibration_rounded,
                                ),
                                title: 'Vibration rhythm',
                                trailing: _buildTrailingTextWithChevron(
                                  _vibrationMode,
                                ),
                                onTap: () {
                                  final modes = [
                                    'Continuous',
                                    'Heartbeat',
                                    'SOS Strobe',
                                    'None',
                                  ];
                                  showModalBottomSheet(
                                    context: context,
                                    backgroundColor: const Color(0xFF1C1C1E),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(22),
                                      ),
                                    ),
                                    builder: (ctx) => Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Vibration Rhythm',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          ...modes.map(
                                            (m) => ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              title: Text(
                                                m,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                              trailing: _vibrationMode == m
                                                  ? const Icon(
                                                      Icons.check_rounded,
                                                      color: Color(0xFF0A84FF),
                                                    )
                                                  : null,
                                              onTap: () {
                                                setState(
                                                  () => _vibrationMode = m,
                                                );
                                                SettingsProvider()
                                                    .setVibrationMode(m);
                                                Navigator.pop(ctx);
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF64D2FF),
                                  Icons.timer_rounded,
                                ),
                                title: 'Auto-silence duration',
                                trailing: _buildTrailingTextWithChevron(
                                  _alarmAutoSilence,
                                ),
                                onTap: () {
                                  final silences = [
                                    'Never',
                                    '30 seconds',
                                    '60 seconds',
                                  ];
                                  showModalBottomSheet(
                                    context: context,
                                    backgroundColor: const Color(0xFF1C1C1E),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(22),
                                      ),
                                    ),
                                    builder: (ctx) => Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Auto-Silence Timeout',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          ...silences.map(
                                            (s) => ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              title: Text(
                                                s,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                              trailing: _alarmAutoSilence == s
                                                  ? const Icon(
                                                      Icons.check_rounded,
                                                      color: Color(0xFF0A84FF),
                                                    )
                                                  : null,
                                              onTap: () {
                                                setState(
                                                  () => _alarmAutoSilence = s,
                                                );
                                                SettingsProvider()
                                                    .setAlarmAutoSilence(s);
                                                Navigator.pop(ctx);
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const _SettingsSubgroup('VOICE ALERTS'),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF34C759),
                                  Icons.record_voice_over_rounded,
                                ),
                                title: 'Voice announcements',
                                subtitle: 'Speak symbol and target price aloud when triggered',
                                trailing: _buildSwitch(
                                  value: _ttsEnabled,
                                  onChanged: (v) {
                                    setState(() => _ttsEnabled = v);
                                    SettingsProvider().setTtsEnabled(v);
                                  },
                                ),
                              ),
                              if (_ttsEnabled)
                                _buildRowItem(
                                  icon: _buildIconBadge(
                                    const Color(0xFF30D158),
                                    Icons.speed_rounded,
                                  ),
                                  title: 'Voice speech rate',
                                  trailing: _buildTrailingTextWithChevron(
                                    _ttsSpeechRate,
                                  ),
                                  onTap: () {
                                    final rates = [
                                      '0.8x',
                                      '1.0x',
                                      '1.2x',
                                      '1.5x',
                                    ];
                                    showModalBottomSheet(
                                      context: context,
                                      backgroundColor: const Color(0xFF1C1C1E),
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(22),
                                        ),
                                      ),
                                      builder: (ctx) => Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Speech Rate',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            ...rates.map(
                                              (r) => ListTile(
                                                contentPadding: EdgeInsets.zero,
                                                title: Text(
                                                  r,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                trailing: _ttsSpeechRate == r
                                                    ? const Icon(
                                                        Icons.check_rounded,
                                                        color: Color(
                                                          0xFF0A84FF,
                                                        ),
                                                      )
                                                    : null,
                                                onTap: () {
                                                  setState(
                                                    () => _ttsSpeechRate = r,
                                                  );
                                                  SettingsProvider()
                                                      .setTtsSpeechRate(r);
                                                  Navigator.pop(ctx);
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              const _SettingsSubgroup('AUDIO EFFECTS'),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF007AFF),
                                  Icons.volume_down_rounded,
                                ),
                                title: 'Audio ducking',
                                subtitle: 'Request Android audio focus so other playback can duck during alarms',
                                trailing: _buildSwitch(
                                  value: _audioDucking,
                                  onChanged: (v) {
                                    setState(() => _audioDucking = v);
                                    SettingsProvider().setAudioDucking(v);
                                  },
                                ),
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFFFFD60A),
                                  Icons.flash_on_rounded,
                                ),
                                title: 'Flashlight strobe alert',
                                subtitle: 'Pulse camera flash in sync with alarm vibrations',
                                trailing: _buildSwitch(
                                  value: _flashlightStrobe,
                                  onChanged: (v) async {
                                    if (v) {
                                      if (!await _alarmService
                                          .isFlashlightAvailable()) {
                                        if (mounted) {
                                          setState(
                                            () => _flashlightStrobe = false,
                                          );
                                        }
                                        return;
                                      }
                                      if (!await _alarmService
                                          .requestCameraPermission()) {
                                        if (mounted) {
                                          setState(
                                            () => _flashlightStrobe = false,
                                          );
                                        }
                                        return;
                                      }
                                    }
                                    if (!context.mounted) return;
                                    setState(() => _flashlightStrobe = v);
                                    await SettingsProvider()
                                        .setFlashlightStrobe(v);
                                  },
                                ),
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFFAF52DE),
                                  Icons.headphones_rounded,
                                ),
                                title: 'Connected audio volume limiter',
                                subtitle: 'Caps alarm output at 70% on wired, USB, and Bluetooth audio outputs',
                                trailing: _buildSwitch(
                                  value: _headphoneSafety,
                                  onChanged: (v) {
                                    setState(() => _headphoneSafety = v);
                                    SettingsProvider().setHeadphoneSafety(v);
                                  },
                                ),
                                showDivider: false,
                              ),
                            ]),

                          // ==========================================
                          // 4. AI DELIBERATION
                          // ==========================================
                          if (widget.initialCategory == 'AI DELIBERATION')
                            _buildCardGroup([
                              const _SettingsSubgroup('AI MODEL'),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFFAF52DE),
                                  Icons.psychology_rounded,
                                ),
                                title: 'AI provider',
                                subtitle: 'App-wide provider configuration',
                                trailing: const Text(
                                  'Managed',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Color(0x9EEBEBF5),
                                  ),
                                ),
                              ),
                              const _SettingsSubgroup('EXECUTION'),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF34C759),
                                  Icons.alt_route_rounded,
                                ),
                                title: 'Execution strategy',
                                trailing: _buildTrailingTextWithChevron(
                                  _aiExecutionStrategy,
                                ),
                                onTap: () {
                                  final strats = ['Parallel', 'Sequential'];
                                  showModalBottomSheet(
                                    context: context,
                                    backgroundColor: const Color(0xFF1C1C1E),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(22),
                                      ),
                                    ),
                                    builder: (ctx) => Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Multi-Agent Execution',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          ...strats.map(
                                            (s) => ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              title: Text(
                                                s,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                              subtitle: Text(
                                                s == 'Parallel'
                                                    ? 'Fast concurrent deliberation across all specialists'
                                                    : 'One by one to preserve strict API quotas',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0x8EEBEBF5),
                                                ),
                                              ),
                                              trailing:
                                                  _aiExecutionStrategy == s
                                                  ? const Icon(
                                                      Icons.check_rounded,
                                                      color: Color(0xFF0A84FF),
                                                    )
                                                  : null,
                                              onTap: () {
                                                setState(
                                                  () =>
                                                      _aiExecutionStrategy = s,
                                                );
                                                SettingsProvider()
                                                    .setAiExecutionStrategy(s);
                                                Navigator.pop(ctx);
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const _SettingsSubgroup('RESPONSE STYLE'),
                              // Temperature Slider Row
                              KeyedSubtree(
                                key: _settingRowKeys.putIfAbsent(
                                  'Temperature',
                                  GlobalKey.new,
                                ),
                                child: Column(
                                  children: [
                                    Container(
                                      constraints: const BoxConstraints(
                                        minHeight: 48,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        children: [
                                          _buildIconBadge(
                                            const Color(0xFFFF9F0A),
                                            Icons.thermostat_rounded,
                                          ),
                                          const SizedBox(width: 12),
                                          const Text(
                                            'Temperature',
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: Colors.white,
                                              letterSpacing: -0.2,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: SliderTheme(
                                              data: SliderTheme.of(context)
                                                  .copyWith(
                                                    activeTrackColor:
                                                        Colors.white,
                                                    inactiveTrackColor:
                                                        const Color(0xFF3A3A3C),
                                                    thumbColor: Colors.white,
                                                    trackHeight: 3,
                                                    thumbShape:
                                                        const RoundSliderThumbShape(
                                                          enabledThumbRadius: 6,
                                                        ),
                                                    overlayShape:
                                                        SliderComponentShape
                                                            .noOverlay,
                                                  ),
                                              child: Slider(
                                                value: _llmTemperature,
                                                min: 0.0,
                                                max: 1.0,
                                                onChanged: (val) {
                                                  setState(
                                                    () => _llmTemperature = val,
                                                  );
                                                  SettingsProvider()
                                                      .setLlmTemperature(val);
                                                },
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _llmTemperature.toStringAsFixed(2),
                                            style: const TextStyle(
                                              color: Color(0x9EEBEBF5),
                                              fontSize: 13,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ]),

                          if (widget.initialCategory == 'ALERTS & SNOOZE')
                            _buildCardGroup([
                              const _SettingsSubgroup('SNOOZE'),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFFFF9F0A),
                                  Icons.snooze_rounded,
                                ),
                                title: 'Default snooze duration',
                                trailing: _buildTrailingTextWithChevron(
                                  '$_defaultSnoozeMinutes min',
                                ),
                                onTap: () {
                                  final snoozes = [3, 5, 10, 15];
                                  showModalBottomSheet(
                                    context: context,
                                    backgroundColor: const Color(0xFF1C1C1E),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(22),
                                      ),
                                    ),
                                    builder: (ctx) => Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Default Snooze Duration',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          ...snoozes.map(
                                            (m) => ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              title: Text(
                                                '$m minutes',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                              trailing:
                                                  _defaultSnoozeMinutes == m
                                                  ? const Icon(
                                                      Icons.check_rounded,
                                                      color: Color(0xFF0A84FF),
                                                    )
                                                  : null,
                                              onTap: () {
                                                setState(
                                                  () =>
                                                      _defaultSnoozeMinutes = m,
                                                );
                                                SettingsProvider()
                                                    .setDefaultSnoozeMinutes(m);
                                                Navigator.pop(ctx);
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const _SettingsSubgroup('ALERT EXPIRATION'),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF64D2FF),
                                  Icons.hourglass_bottom_rounded,
                                ),
                                title: 'Stale alert expiration',
                                subtitle: 'Automatically deactivate unhit price alerts after period',
                                trailing: _buildTrailingTextWithChevron(
                                  _alertTtl,
                                ),
                                onTap: () {
                                  final ttls = [
                                    'Never',
                                    '24 Hours',
                                    '3 Days',
                                    '1 Week',
                                  ];
                                  showModalBottomSheet(
                                    context: context,
                                    backgroundColor: const Color(0xFF1C1C1E),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(22),
                                      ),
                                    ),
                                    builder: (ctx) => Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Alert Expiration',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          ...ttls.map(
                                            (t) => ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              title: Text(
                                                t,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                              trailing: _alertTtl == t
                                                  ? const Icon(
                                                      Icons.check_rounded,
                                                      color: Color(0xFF0A84FF),
                                                    )
                                                  : null,
                                              onTap: () {
                                                setState(() => _alertTtl = t);
                                                SettingsProvider().setAlertTtl(
                                                  t,
                                                );
                                                Navigator.pop(ctx);
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ]),

                          if (widget.initialCategory == 'CHARTS & TERMINAL')
                            _buildCardGroup([
                              const _SettingsSubgroup('STARTUP'),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF0A84FF),
                                  Icons.launch_rounded,
                                ),
                                title: 'Default launch screen',
                                trailing: _buildTrailingTextWithChevron(
                                  _defaultLaunchScreen,
                                ),
                                onTap: () {
                                  final screens = [
                                    'Market Watch',
                                    'Markets Hub',
                                    'AI Deliberation',
                                  ];
                                  showModalBottomSheet(
                                    context: context,
                                    backgroundColor: const Color(0xFF1C1C1E),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(22),
                                      ),
                                    ),
                                    builder: (ctx) => Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Initial App Screen',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          ...screens.map(
                                            (s) => ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              title: Text(
                                                s,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                              trailing:
                                                  _defaultLaunchScreen == s
                                                  ? const Icon(
                                                      Icons.check_rounded,
                                                      color: Color(0xFF0A84FF),
                                                    )
                                                  : null,
                                              onTap: () {
                                                setState(
                                                  () =>
                                                      _defaultLaunchScreen = s,
                                                );
                                                SettingsProvider()
                                                    .setDefaultLaunchScreen(s);
                                                Navigator.pop(ctx);
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const _SettingsSubgroup('CHART DEFAULTS'),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF30D158),
                                  Icons.bar_chart_rounded,
                                ),
                                title: 'Default timeframe',
                                trailing: _buildTrailingTextWithChevron(
                                  _defaultChartTimeframe,
                                ),
                                onTap: () {
                                  final tfs = [
                                    '1m',
                                    '5m',
                                    '15m',
                                    '30m',
                                    '1H',
                                    '4H',
                                    '1D',
                                  ];
                                  showModalBottomSheet(
                                    context: context,
                                    backgroundColor: const Color(0xFF1C1C1E),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(22),
                                      ),
                                    ),
                                    builder: (ctx) => Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Default Timeframe',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          ...tfs.map(
                                            (t) => ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              title: Text(
                                                t,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                              trailing:
                                                  _defaultChartTimeframe == t
                                                  ? const Icon(
                                                      Icons.check_rounded,
                                                      color: Color(0xFF0A84FF),
                                                    )
                                                  : null,
                                              onTap: () {
                                                setState(
                                                  () => _defaultChartTimeframe =
                                                      t,
                                                );
                                                SettingsProvider()
                                                    .setDefaultChartTimeframe(
                                                      t,
                                                    );
                                                Navigator.pop(ctx);
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFFFF9F0A),
                                  Icons.candlestick_chart_outlined,
                                ),
                                title: 'Candlestick style',
                                trailing: _buildTrailingTextWithChevron(
                                  _chartCandleType,
                                ),
                                onTap: () {
                                  final types = [
                                    'Japanese Candles',
                                    'Hollow Candles',
                                    'Line Chart',
                                  ];
                                  showModalBottomSheet(
                                    context: context,
                                    backgroundColor: const Color(0xFF1C1C1E),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(22),
                                      ),
                                    ),
                                    builder: (ctx) => Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Candle Style',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          ...types.map(
                                            (type) => ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              title: Text(
                                                type,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                              trailing: _chartCandleType == type
                                                  ? const Icon(
                                                      Icons.check_rounded,
                                                      color: Color(0xFF0A84FF),
                                                    )
                                                  : null,
                                              onTap: () {
                                                setState(
                                                  () => _chartCandleType = type,
                                                );
                                                SettingsProvider()
                                                    .setChartCandleType(type);
                                                Navigator.pop(ctx);
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF64D2FF),
                                  Icons.timer_outlined,
                                ),
                                title: 'Candle countdown timer',
                                subtitle: 'Display remaining time until current bar closes',
                                trailing: _buildSwitch(
                                  value: _showCandleCountdown,
                                  onChanged: (v) {
                                    setState(() => _showCandleCountdown = v);
                                    SettingsProvider().setShowCandleCountdown(
                                      v,
                                    );
                                  },
                                ),
                              ),
                              const _SettingsSubgroup('CHART INTERACTION'),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF5E5CE6),
                                  Icons.vibration_rounded,
                                ),
                                title: 'Tactile line drag',
                                subtitle: 'Haptic feedback while dragging chart lines or the crosshair',
                                trailing: _buildSwitch(
                                  value: _vibrateOnDrag,
                                  onChanged: (v) {
                                    setState(() => _vibrateOnDrag = v);
                                    SettingsProvider().setVibrateOnDrag(v);
                                  },
                                ),
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFFBF5AF2),
                                  Icons.auto_awesome_rounded,
                                ),
                                title: 'Magnetic snapping',
                                subtitle: 'Snap chart lines to candle OHLC values and nearby round prices',
                                trailing: _buildSwitch(
                                  value: _magneticSnapping,
                                  onChanged: (v) {
                                    setState(() => _magneticSnapping = v);
                                    SettingsProvider().setMagneticSnapping(v);
                                  },
                                ),
                              ),
                              const _SettingsSubgroup('CHART APPEARANCE'),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF34C759),
                                  Icons.gradient_rounded,
                                ),
                                title: 'Market session shading',
                                subtitle: 'Render background highlights for Tokyo, London, and NY hours',
                                trailing: _buildSwitch(
                                  value: _sessionShading,
                                  onChanged: (v) {
                                    setState(() => _sessionShading = v);
                                    SettingsProvider().setSessionShading(v);
                                  },
                                ),
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFFFFD60A),
                                  Icons.palette_rounded,
                                ),
                                title: 'Color palette mode',
                                trailing: _buildTrailingTextWithChevron(
                                  _colorblindChartMode,
                                ),
                                onTap: () {
                                  final modes = [
                                    'Standard',
                                    'Deuteranopia',
                                    'Monochrome OLED',
                                  ];
                                  showModalBottomSheet(
                                    context: context,
                                    backgroundColor: const Color(0xFF1C1C1E),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(22),
                                      ),
                                    ),
                                    builder: (ctx) => Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Color Palette Mode',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          ...modes.map(
                                            (mode) => ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              title: Text(
                                                mode,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                              trailing:
                                                  _colorblindChartMode == mode
                                                  ? const Icon(
                                                      Icons.check_rounded,
                                                      color: Color(0xFF0A84FF),
                                                    )
                                                  : null,
                                              onTap: () {
                                                setState(
                                                  () => _colorblindChartMode =
                                                      mode,
                                                );
                                                SettingsProvider()
                                                    .setColorblindChartMode(
                                                      mode,
                                                    );
                                                Navigator.pop(ctx);
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                                showDivider: false,
                              ),
                            ]),

                          // ==========================================
                          // 7. DATA & BACKUP
                          // ==========================================
                          if (widget.initialCategory == 'DATA & BACKUP')
                            _buildCardGroup([
                              const _SettingsSubgroup('BACKUP & SECURITY'),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF0A84FF),
                                  Icons.file_download_rounded,
                                ),
                                title: 'Export backup',
                                subtitle: 'Save user settings, agents, and strategies',
                                trailing: _buildTrailingTextWithChevron(
                                  'Export',
                                ),
                                onTap: _exportBackupJson,
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF30D158),
                                  Icons.file_upload_rounded,
                                ),
                                title: 'Restore backup',
                                subtitle:
                                    'Restore from a copied TenX JSON backup',
                                trailing: _buildTrailingTextWithChevron(
                                  'Import',
                                ),
                                onTap: _showRestoreBackupDialog,
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF5E5CE6),
                                  Icons.fingerprint_rounded,
                                ),
                                title: 'Biometric app lock',
                                subtitle:
                                    'Require Fingerprint or PIN to resume app',
                                trailing: _buildSwitch(
                                  value: _biometricAppLock,
                                  onChanged: (v) async {
                                    if (v) {
                                      final auth = await _alarmService
                                          .authenticateBiometrics();
                                      if (!auth) {
                                        if (!mounted || !context.mounted) {
                                          return;
                                        }
                                        TenXToast.show(
                                          context,
                                          title: 'Authentication Failed',
                                          subtitle: 'Biometric or device PIN verification required to enable lock.',
                                        );
                                        return;
                                      }
                                    }
                                    try {
                                      await SettingsProvider()
                                          .setBiometricAppLock(v);
                                      if (mounted) {
                                        setState(() => _biometricAppLock = v);
                                      }
                                    } catch (_) {
                                      if (mounted && context.mounted) {
                                        TenXToast.show(
                                          context,
                                          title: 'Lock Setting Not Saved',
                                          subtitle: 'The app could not persist this security preference.',
                                        );
                                      }
                                    }
                                  },
                                ),
                              ),
                              const _SettingsSubgroup('DIAGNOSTICS'),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFFFF9F0A),
                                  Icons.table_chart_rounded,
                                ),
                                title: 'Export trading journal',
                                subtitle: 'Copy alert history and AI specialist votes to CSV',
                                trailing: _buildTrailingTextWithChevron('CSV'),
                                onTap: _exportTradingJournalCsv,
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF64D2FF),
                                  Icons.network_check_rounded,
                                ),
                                title: 'System diagnostics ping',
                                subtitle: 'Check SignalR, candles, AI, and daemon status',
                                trailing: _buildTrailingTextWithChevron(
                                  'Run test',
                                ),
                                onTap: _runFullDiagnostics,
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF30D158),
                                  Icons.terminal_rounded,
                                ),
                                title: 'Device telemetry',
                                subtitle: 'Inspect OS platform, daemon PID, and memory',
                                trailing: _buildTrailingTextWithChevron(
                                  'Inspect',
                                ),
                                onTap: _showDiagnosticsTerminalModal,
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF0A84FF),
                                  Icons.share_rounded,
                                ),
                                title: 'Share diagnostic log',
                                subtitle:
                                    'Sanitized report with API keys redacted',
                                trailing: _buildTrailingTextWithChevron(
                                  'Share',
                                ),
                                onTap: _shareSanitizedReport,
                              ),
                              const _SettingsSubgroup('LOCAL DATA'),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFFFF9F0A),
                                  Icons.delete_sweep_rounded,
                                ),
                                title: 'Clear candle cache',
                                subtitle:
                                    'Purge locally cached historical candles',
                                trailing: _buildTrailingTextWithChevron(
                                  'Purge',
                                ),
                                onTap: () async {
                                  try {
                                    final purged =
                                        await RealMarketService.clearCandleCache();
                                    if (!context.mounted) return;
                                    TenXToast.show(
                                      context,
                                      title: 'Cache Purged',
                                      subtitle:
                                          'Removed $purged cached historical bars.',
                                    );
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    TenXToast.show(
                                      context,
                                      title: 'Cache clear failed',
                                      subtitle: '$e',
                                    );
                                  }
                                },
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF8E8E93),
                                  Icons.cleaning_services_rounded,
                                ),
                                title: 'Clear alert history',
                                subtitle: 'Purge triggered records without affecting active alerts',
                                trailing: _buildTrailingTextWithChevron(
                                  'Purge',
                                ),
                                onTap: () async {
                                  final manager = widget.alertManager;
                                  if (manager == null) {
                                    TenXToast.show(
                                      context,
                                      title: 'History clear failed',
                                      subtitle: 'Alert storage is unavailable.',
                                    );
                                    return;
                                  }
                                  try {
                                    await manager.clearHistory();
                                    if (!context.mounted) return;
                                    TenXToast.show(
                                      context,
                                      title: 'History Purged',
                                      subtitle: 'Fired alert records cleared.',
                                    );
                                  } catch (e) {
                                    if (!mounted) return;
                                    TenXToast.show(
                                      context,
                                      title: 'History clear failed',
                                      subtitle: '$e',
                                    );
                                  }
                                },
                              ),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFFFF453A),
                                  Icons.restore_rounded,
                                ),
                                title: 'Reset to factory defaults',
                                trailing: _buildTrailingTextWithChevron(
                                  'Reset',
                                  color: const Color(0xFFFF453A),
                                ),
                                onTap: _confirmFactoryReset,
                                showDivider: false,
                              ),
                            ]),

                          // ==========================================
                          // 8. ABOUT
                          // ==========================================
                          if (widget.initialCategory == 'ABOUT')
                            _buildCardGroup([
                              const _SettingsSubgroup('APP'),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF8E8E93),
                                  Icons.info_outline_rounded,
                                ),
                                title: 'Version',
                                trailing: const Text(
                                  '1.0.0 (build 1)',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Color(0x9EEBEBF5),
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                showDivider: false,
                              ),
                              const _SettingsSubgroup('CREDITS'),
                              _buildRowItem(
                                icon: _buildIconBadge(
                                  const Color(0xFF0A84FF),
                                  Icons.person_outline_rounded,
                                ),
                                title: 'Built by',
                                subtitle: 'Gift Braimah',
                                showDivider: false,
                              ),
                            ]),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
