import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/app_telemetry.dart';

import '../models/ai_models.dart';
import '../models/market_models.dart';
import '../services/biquote_service.dart';
import '../services/alert_manager.dart';
import '../services/settings_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_toast_bar.dart';
import 'alarm_fired_screen.dart';
import 'chart_screen.dart';
import 'strategies_screen.dart';
import 'history_screen.dart';
import 'markets_hub_screen.dart';
import 'settings_screen.dart';
import 'account_screen.dart';

class MainNavigation extends StatefulWidget {
  final BiquoteService biquoteService;
  final AlertManager alertManager;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final Map<String, dynamic>? initialAlarm;
  final User user;

  const MainNavigation({
    super.key,
    required this.biquoteService,
    required this.alertManager,
    required this.isDark,
    required this.onToggleTheme,
    this.initialAlarm,
    required this.user,
  });

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation>
    with WidgetsBindingObserver {
  final GlobalKey<ChartScreenState> _chartScreenKey =
      GlobalKey<ChartScreenState>();
  int _currentIndex = 0;
  bool _batteryOptimizationIgnored = true;
  bool _isAppLocked = false;
  bool _isAlarmHudVisible = false;
  final Set<String> _dismissedHudEvents = <String>{};
  bool _isAuthenticating = false;
  bool _shouldLockOnResume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkBatteryOptimization();
    if (widget.initialAlarm == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _requestStartupPermissions(),
      );
    }

    final launchScreen = SettingsProvider().defaultLaunchScreen;
    if (launchScreen.contains('Calendar') || launchScreen.contains('Markets')) {
      _currentIndex = 3;
    } else if (launchScreen.contains('Deliberation') ||
        launchScreen.contains('AI')) {
      _currentIndex = 2;
    } else if (launchScreen.contains('Alert') ||
        launchScreen.contains('History')) {
      _currentIndex = 1;
    } else {
      _currentIndex = 0;
    }
    _isAppLocked = SettingsProvider().biometricAppLock;
    unawaited(AppTelemetry.logScreen(_screenName(_currentIndex)));
    if (_isAppLocked) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _performBiometricUnlock(),
      );
    }

    // Hook up global alert trigger callback to show full HUD AlarmFiredScreen
    widget.alertManager.onAlertTriggered = _showAlarmFiredHUD;

    // Listen to native OS background alarm triggers
    const MethodChannel('com.example.alert_app/alarm')
        .setMethodCallHandler(_handleNativeAlarmCall);
    if (widget.initialAlarm != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showAlarmFromArgs(widget.initialAlarm!),
      );
    }
  }

  void _showAlarmFromArgs(Map<String, dynamic> args) {
    final symbol = args['symbol']?.toString() ?? 'EURUSD';
    final triggerPrice = (args['triggerPrice'] as num?)?.toDouble() ?? 0.0;
    PriceAlert? alert;
    try {
      alert = widget.alertManager.activeAlerts.firstWhere(
        (a) => a.symbol == symbol,
      );
    } catch (_) {
      alert = PriceAlert(
        id: 'bg_${DateTime.now().millisecondsSinceEpoch}',
        symbol: symbol,
        targetPrice: triggerPrice,
        initialPrice: triggerPrice,
        condition: AlertCondition.crossesAbove,
        createdAt: DateTime.now(),
        note: 'Market Alert Triggered',
      );
    }
    _showAlarmFiredHUD(alert, triggerPrice);
  }

  Future<dynamic> _handleNativeAlarmCall(MethodCall call) async {
    if (call.method == 'onAlarmTriggered') {
      final Map<dynamic, dynamic>? args =
          call.arguments as Map<dynamic, dynamic>?;
      if (args != null) _showAlarmFromArgs(Map<String, dynamic>.from(args));
    }
    return null;
  }

  Future<void> _performBiometricUnlock() async {
    // The Android credential confirmation activity backgrounds this activity.
    // Ignore that lifecycle transition while authentication itself is active;
    // otherwise its return immediately starts a second prompt and re-locks us.
    if (_isAuthenticating || !mounted) return;
    _isAuthenticating = true;
    try {
      final success = await widget.alertManager.alarmService
          .authenticateBiometrics();
      if (success && mounted) {
        setState(() => _isAppLocked = false);
      }
    } finally {
      _isAuthenticating = false;
    }
  }

  void _showAlarmFiredHUD(PriceAlert alert, double triggerPrice) {
    final eventKey =
        '${alert.id}|${alert.triggeredAt?.millisecondsSinceEpoch ?? ''}|${triggerPrice.toStringAsPrecision(12)}';
    if (!mounted ||
        _isAlarmHudVisible ||
        _dismissedHudEvents.contains(eventKey)) {
      return;
    }
    _isAlarmHudVisible = true;
    Navigator.of(context)
        .push(
          PageRouteBuilder(
            opaque: true,
            pageBuilder: (context, animation, secondaryAnimation) =>
                AlarmFiredScreen(
                  alert: alert,
                  triggerPrice: triggerPrice,
                  alarmService: widget.alertManager.alarmService,
                  onDismiss: () {
                    widget.alertManager.alarmService.stopAlarm();
                  },
                  onSnooze: () {
                    widget.alertManager.snoozeAlert(alert.id);
                  },
                  onOpenTerminal: (sym) {
                    _switchToChart(sym);
                  },
                ),
            transitionsBuilder: (context, animation, _, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        )
        .whenComplete(() {
          _dismissedHudEvents.add(eventKey);
          if (_dismissedHudEvents.length > 64) {
            _dismissedHudEvents.remove(_dismissedHudEvents.first);
          }
          _isAlarmHudVisible = false;
        });
  }

  Future<void> _requestStartupPermissions() async {
    if (!mounted || Theme.of(context).platform != TargetPlatform.android) {
      return;
    }
    final service = widget.alertManager.alarmService;
    Future<bool> offer(
      String title,
      String explanation,
      Future<bool> Function() check,
      Future<void> Function() request,
    ) async {
      if (await check() || !mounted) return true;
      final grant = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(explanation),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Set up'),
            ),
          ],
        ),
      );
      if (grant == true) await request();
      return grant ?? false;
    }

    await offer(
      'Allow notifications',
      'TenX needs notifications to show price alerts and monitoring status.',
      service.areNotificationsEnabled,
      service.requestNotificationPermission,
    );
    await offer(
      'Show alerts on the lock screen',
      'Allow full screen alert notifications so alerts can appear while the phone is locked.',
      service.isFullScreenIntentAllowed,
      service.requestFullScreenIntentPermission,
    );
    await offer(
      'Show alerts over other apps',
      'Allow TenX to show the full alert HUD while another app is open. You can change this permission in Android Settings.',
      service.isOverlayPermissionGranted,
      service.requestOverlayPermission,
    );
    await offer(
      'Allow background monitoring',
      'Battery optimization can stop market monitoring and reconnect attempts when TenX is in the background.',
      service.isBatteryOptimizationIgnored,
      service.requestIgnoreBatteryOptimizations,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && !_isAuthenticating) {
      // Re-lock only when the user actually leaves the app. Android's system
      // credential screen also changes lifecycle state, but is covered above.
      _shouldLockOnResume = true;
    } else if (state == AppLifecycleState.resumed) {
      _checkBatteryOptimization();
      widget.alertManager.reloadAndSync();
      final shouldReauthenticate = _shouldLockOnResume;
      _shouldLockOnResume = false;
      if (shouldReauthenticate && SettingsProvider().biometricAppLock) {
        setState(() => _isAppLocked = true);
        _performBiometricUnlock();
      }
    }
  }

  Future<void> _checkBatteryOptimization() async {
    try {
      final isIgnored = await widget.alertManager.alarmService
          .isBatteryOptimizationIgnored();
      if (mounted) {
        setState(() {
          _batteryOptimizationIgnored = isIgnored;
        });
      }
    } catch (_) {}
  }

  void _switchToChart([String? symbol, AgentSignal? signal]) {
    if (_currentIndex != 0) unawaited(AppTelemetry.logScreen('chart'));
    setState(() {
      _currentIndex = 0;
    });
    final targetSymbol = (symbol != null && symbol.isNotEmpty)
        ? symbol
        : (signal?.symbol != null && signal!.symbol!.isNotEmpty)
        ? signal.symbol!
        : (_chartScreenKey.currentState?.selectedSymbol ?? 'EURUSD');
    _chartScreenKey.currentState?.selectSymbol(
      targetSymbol,
      signalOverlay: signal,
    );
  }

  void _switchToAlerts() {
    if (_currentIndex != 1) unawaited(AppTelemetry.logScreen('alerts'));
    setState(() {
      _currentIndex = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = math.max(
      16.0,
      MediaQuery.of(context).padding.bottom + 6,
    );

    final screens = [
      // 0: Chart
      ChartScreen(
        key: _chartScreenKey,
        biquoteService: widget.biquoteService,
        alertManager: widget.alertManager,
        isDark: isDark,
        onToggleTheme: widget.onToggleTheme,
      ),
      // 1: Alerts & History
      HistoryScreen(
        onNavigateToChart: () => _switchToChart(),
        onSelectSymbolForChart: (sym) => _switchToChart(sym),
        onSelectSignalForChart: (sig) => _switchToChart(sig.symbol, sig),
        alertManager: widget.alertManager,
        biquoteService: widget.biquoteService,
        initialAlertSymbol:
            _chartScreenKey.currentState?.selectedSymbol ?? 'EURUSD',
        initialAlertPrice:
            _chartScreenKey.currentState?.selectedCurrentPrice ?? 0,
        initialAlertPrecision:
            _chartScreenKey.currentState?.selectedPrecision ?? 5,
      ),
      // 2: AI Multi-Agent Pipeline
      StrategiesScreen(
        isDark: isDark,
        onNavigateToChart: () => _switchToChart(),
        onSelectSymbolForChart: (sym) => _switchToChart(sym),
        onSelectSignalForChart: (sig) => _switchToChart(sig.symbol, sig),
        onNavigateToHistory: _switchToAlerts,
        biquoteService: widget.biquoteService,
        alertManager: widget.alertManager,
      ),
      // 3: Markets
      MarketsHubScreen(
        onSelectSymbol: (sym) => _switchToChart(sym),
        alertManager: widget.alertManager,
      ),
      // 4: More / Settings
      SettingsScreen(
        isDark: isDark,
        onToggleTheme: widget.onToggleTheme,
        alertManager: widget.alertManager,
        biquoteService: widget.biquoteService,
        onManageAccount: _openAccount,
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main screen views
          Positioned.fill(
            child: Column(
              children: [
                if (!_batteryOptimizationIgnored) _buildBatteryBanner(),
                Expanded(
                  child: IndexedStack(index: _currentIndex, children: screens),
                ),
              ],
            ),
          ),

          // Floating Frosted Pill Bottom Navigation Bar
          Positioned(
            left: 14,
            right: 14,
            bottom: bottomInset,
            child: _buildFloatingBottomNav(),
          ),

          // Biometric / PIN Lock Shield Screen
          if (_isAppLocked) Positioned.fill(child: _buildBiometricLockScreen()),

          // Keep the announcement in the app shell so pushed alarm screens
          // always appear above it and remain unobstructed.
          if (!_isAppLocked)
            Positioned.fill(
              child: AdminToastBarHost(bottomOffset: bottomInset + 66 + 16),
            ),
        ],
      ),
    );
  }

  void _openAccount() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AccountScreen(user: widget.user)),
    );
  }

  Widget _buildBiometricLockScreen() {
    return Container(
      color: Colors.black.withValues(alpha: 0.95),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF0A84FF).withValues(alpha: 0.15),
                      border: Border.all(
                        color: const Color(0xFF0A84FF),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0A84FF).withValues(alpha: 0.4),
                          blurRadius: 30,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.fingerprint_rounded,
                      size: 44,
                      color: Color(0xFF0A84FF),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'TenX Security Shield',
                    style: AppTheme.sans(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Biometric or PIN authentication required to access trading terminal & active alerts.',
                    textAlign: TextAlign.center,
                    style: AppTheme.sans(
                      fontSize: 13,
                      color: const Color.fromRGBO(235, 235, 245, 0.60),
                    ),
                  ),
                  const SizedBox(height: 36),
                  ElevatedButton.icon(
                    onPressed: _performBiometricUnlock,
                    icon: const Icon(Icons.fingerprint_rounded, size: 20),
                    label: const Text('Unlock with Biometrics / PIN'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0A84FF),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: AppTheme.sans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingBottomNav() {
    return Container(
      height: 66,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(33),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.50),
            blurRadius: 24,
            spreadRadius: 2,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(33),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(44, 44, 46, 0.72),
              borderRadius: BorderRadius.circular(33),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.09),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                _buildNavItem(
                  index: 0,
                  label: 'Chart',
                  iconType: _NavIconType.chart,
                ),
                _buildNavItem(
                  index: 1,
                  label: 'Alerts',
                  iconType: _NavIconType.alerts,
                ),
                _buildNavItem(index: 2, label: 'AI', iconType: _NavIconType.ai),
                _buildNavItem(
                  index: 3,
                  label: 'Markets',
                  iconType: _NavIconType.markets,
                ),
                _buildNavItem(
                  index: 4,
                  label: 'More',
                  iconType: _NavIconType.more,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required String label,
    required _NavIconType iconType,
  }) {
    final isSelected = _currentIndex == index;
    final color = isSelected
        ? const Color(0xFF0A84FF)
        : const Color.fromRGBO(235, 235, 245, 0.62);

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_currentIndex != index) {
            unawaited(AppTelemetry.logScreen(_screenName(index)));
            setState(() {
              _currentIndex = index;
            });
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 54,
          decoration: BoxDecoration(
            color: isSelected
                ? const Color.fromRGBO(10, 132, 255, 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(27),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CustomPaint(
                size: const Size(22, 22),
                painter: _NavIconPainter(type: iconType, color: color),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: AppTheme.sans(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: -0.1,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBatteryBanner() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 6,
        bottom: 8,
        left: 14,
        right: 14,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.amber.shade900, Colors.deepOrange.shade800],
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.battery_alert_rounded,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Allow 24/7 background run so alarms trigger when phone sleeps.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onPressed: () async {
              await widget.alertManager.alarmService
                  .requestIgnoreBatteryOptimizations();
              Future.delayed(
                const Duration(seconds: 2),
                _checkBatteryOptimization,
              );
            },
            child: const Text(
              'ALLOW',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

String _screenName(int index) => switch (index) {
  0 => 'chart',
  1 => 'alerts',
  2 => 'ai_strategies',
  3 => 'markets',
  _ => 'settings',
};

enum _NavIconType { chart, alerts, ai, markets, more }

class _NavIconPainter extends CustomPainter {
  final _NavIconType type;
  final Color color;

  _NavIconPainter({required this.type, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    canvas.save();
    canvas.scale(scale, scale);

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (type) {
      case _NavIconType.chart:
        // Wicks
        canvas.drawLine(const Offset(7, 4), const Offset(7, 7), strokePaint);
        canvas.drawLine(const Offset(7, 17), const Offset(7, 20), strokePaint);
        canvas.drawLine(const Offset(17, 8), const Offset(17, 11), strokePaint);
        canvas.drawLine(
          const Offset(17, 18),
          const Offset(17, 20),
          strokePaint,
        );
        // Candle Bodies
        final r1 = RRect.fromRectAndRadius(
          const Rect.fromLTWH(5, 7, 4, 10),
          const Radius.circular(1),
        );
        final r2 = RRect.fromRectAndRadius(
          const Rect.fromLTWH(15, 11, 4, 7),
          const Radius.circular(1),
        );
        canvas.drawRRect(r1, strokePaint);
        canvas.drawRRect(r2, strokePaint);
        break;

      case _NavIconType.alerts:
        // Bell path: M6 16v-5a6 6 0 1112 0v5l1.5 2h-15z
        final path = Path();
        path.moveTo(6, 16);
        path.lineTo(6, 11);
        path.arcToPoint(
          const Offset(18, 11),
          radius: const Radius.circular(6),
          clockwise: true,
        );
        path.lineTo(18, 16);
        path.lineTo(19.5, 18);
        path.lineTo(4.5, 18);
        path.close();
        canvas.drawPath(path, strokePaint);
        // Clapper: M10 21h4
        canvas.drawLine(
          const Offset(10, 21),
          const Offset(14, 21),
          strokePaint,
        );
        break;

      case _NavIconType.ai:
        // 4-pointed Sparkle Star: M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z
        final path = Path();
        path.moveTo(12, 3);
        path.lineTo(13.8, 8.2);
        path.lineTo(19, 10);
        path.lineTo(13.8, 11.8);
        path.lineTo(12, 17);
        path.lineTo(10.2, 11.8);
        path.lineTo(5, 10);
        path.lineTo(10.2, 8.2);
        path.close();
        canvas.drawPath(path, strokePaint);
        break;

      case _NavIconType.markets:
        // 4 rounded rects
        final r1 = RRect.fromRectAndRadius(
          const Rect.fromLTWH(4, 4, 7, 7),
          const Radius.circular(2),
        );
        final r2 = RRect.fromRectAndRadius(
          const Rect.fromLTWH(13, 4, 7, 7),
          const Radius.circular(2),
        );
        final r3 = RRect.fromRectAndRadius(
          const Rect.fromLTWH(4, 13, 7, 7),
          const Radius.circular(2),
        );
        final r4 = RRect.fromRectAndRadius(
          const Rect.fromLTWH(13, 13, 7, 7),
          const Radius.circular(2),
        );
        canvas.drawRRect(r1, strokePaint);
        canvas.drawRRect(r2, strokePaint);
        canvas.drawRRect(r3, strokePaint);
        canvas.drawRRect(r4, strokePaint);
        break;

      case _NavIconType.more:
        // Sliders: M4 7h10M18 7h2M4 17h2M10 17h10 + circles
        canvas.drawLine(const Offset(4, 7), const Offset(14, 7), strokePaint);
        canvas.drawLine(const Offset(18, 7), const Offset(20, 7), strokePaint);
        canvas.drawCircle(const Offset(16, 7), 2.2, strokePaint);

        canvas.drawLine(const Offset(4, 17), const Offset(6, 17), strokePaint);
        canvas.drawLine(
          const Offset(10, 17),
          const Offset(20, 17),
          strokePaint,
        );
        canvas.drawCircle(const Offset(8, 17), 2.2, strokePaint);
        break;
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NavIconPainter oldDelegate) {
    return oldDelegate.type != type || oldDelegate.color != color;
  }
}
