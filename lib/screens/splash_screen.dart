import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/alert_manager.dart';
import '../services/biquote_service.dart';
import '../theme/app_theme.dart';
import '../widgets/splash_sponsor_ad.dart';
import 'main_navigation.dart';

class SplashScreen extends StatefulWidget {
  final BiquoteService biquoteService;
  final AlertManager alertManager;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final User user;

  const SplashScreen({
    super.key,
    required this.biquoteService,
    required this.alertManager,
    required this.isDark,
    required this.onToggleTheme,
    required this.user,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _progressAnimation;

  Timer? _fallbackNavTimer;

  bool _alertsResolved = false;
  final bool _isOnline = true;
  final String _latencyText = '24 ms';
  bool _hasNavigated = false;
  static const _alarmChannel = MethodChannel('com.example.alert_app/alarm');

  @override
  void initState() {
    super.initState();
    widget.alertManager.addListener(_onAlertsChanged);
    _alertsResolved = widget.alertManager.isLoaded;
    _alarmChannel.setMethodCallHandler((call) async {
      if (call.method == 'onAlarmTriggered') {
        _navigateToHome(Map<String, dynamic>.from(call.arguments as Map));
      }
    });
    _alarmChannel
        .invokeMapMethod<String, dynamic>('consumePendingAlarm')
        .then((alarm) {
          if (alarm != null) _navigateToHome(alarm);
        })
        .catchError((_) {});

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3800),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.26, curve: Curves.easeOutCubic),
    );

    _scaleAnimation = Tween<double>(begin: 0.90, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.30, curve: Curves.easeOutCubic),
      ),
    );

    _progressAnimation = Tween<double>(begin: 0.05, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.05, 0.90, curve: Curves.easeInOutCubic),
      ),
    );

    _controller.forward();

    // Unconditional navigation after splash progress completes
    // NEVER waits for or blocks on internet connectivity!
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _navigateToHome();
      }
    });

    _fallbackNavTimer = Timer(const Duration(milliseconds: 3950), () {
      _navigateToHome();
    });
  }

  void _onAlertsChanged() {
    if (!mounted || _alertsResolved || !widget.alertManager.isLoaded) return;
    setState(() => _alertsResolved = true);
  }

  void _navigateToHome([Map<String, dynamic>? initialAlarm]) {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 550),
        reverseTransitionDuration: const Duration(milliseconds: 550),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: MainNavigation(
              biquoteService: widget.biquoteService,
              alertManager: widget.alertManager,
              initialAlarm: initialAlarm,
              user: widget.user,
              isDark: widget.isDark,
              onToggleTheme: widget.onToggleTheme,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    widget.alertManager.removeListener(_onAlertsChanged);
    _fallbackNavTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alertCount = widget.alertManager.activeAlerts.length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Ambient Top Radial Glow (matching Splash.dc.html)
          Positioned(
            top: -120,
            left: -60,
            right: -60,
            height: 560,
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.0, -0.4),
                  radius: 0.85,
                  colors: [
                    Color.fromRGBO(10, 132, 255, 0.45),
                    Color.fromRGBO(100, 210, 255, 0.12),
                    Color(0x00000000),
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),

          // 2. Linear Gradient Fade overlay to pure OLED black
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.40, 0.78, 1.0],
                  colors: [
                    Color(0x00000000),
                    Color(0x00000000),
                    Color(0xFF000000),
                    Color(0xFF000000),
                  ],
                ),
              ),
            ),
          ),

          // 3. Main Screen Content
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Spacer(flex: 3),

                            // Hero Section: App Icon + Typography
                            FadeTransition(
                              opacity: _fadeAnimation,
                              child: ScaleTransition(
                                scale: _scaleAnimation,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // 112x112 App Icon Hero Container (exact match Splash.dc.html lines 29-31)
                                    Container(
                                      width: 112,
                                      height: 112,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(34),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF0A84FF)
                                                .withValues(alpha: 0.50),
                                            blurRadius: 60,
                                            offset: const Offset(0, 24),
                                          ),
                                        ],
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.35,
                                          ),
                                          width: 1.0,
                                        ),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(34),
                                        child: Image.asset(
                                          'assets/tenx_logo.png',
                                          width: 112,
                                          height: 112,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 26),

                                    // Brand Title (exact match Splash.dc.html line 32)
                                    Text(
                                      'TenX',
                                      style: AppTheme.sans(
                                        fontSize: 44,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -1.76, // -.04em
                                        color: Colors.white,
                                        height: 1.05,
                                      ),
                                    ),
                                    const SizedBox(height: 4),

                                    // Subtitle (exact match Splash.dc.html line 33)
                                    Text(
                                      'Alerts and Multi Agent Analysis',
                                      style: AppTheme.sans(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w400,
                                        letterSpacing: -0.16, // -.01em
                                        color: const Color.fromRGBO(
                                          235,
                                          235,
                                          245,
                                          0.62,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const Spacer(flex: 4),

                            // Middle Glass Status Panel
                            FadeTransition(
                              opacity: _fadeAnimation,
                              child: Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.09),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.35,
                                      ),
                                      blurRadius: 24,
                                      offset: const Offset(0, 12),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(
                                      sigmaX: 28,
                                      sigmaY: 28,
                                    ),
                                    child: Container(
                                      color: const Color.fromRGBO(
                                        44,
                                        44,
                                        46,
                                        0.55,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 4,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Row 1: Network Connected
                                          _buildStatusRow(
                                            dotWidget: _buildDot(
                                              color: _isOnline
                                                  ? const Color(0xFF30D158)
                                                  : const Color(0xFFFF9F0A),
                                              icon: _isOnline
                                                  ? Icons.check_rounded
                                                  : Icons.wifi_off_rounded,
                                            ),
                                            title: _isOnline
                                                ? 'Network connected'
                                                : 'Offline standby',
                                            numText: _latencyText,
                                          ),

                                          // Divider
                                          Container(
                                            height: 1,
                                            color: Colors.white.withValues(
                                              alpha: 0.08,
                                            ),
                                          ),

                                          // Row 2: Biquote Live Feed
                                          _buildStatusRow(
                                            dotWidget: _buildDot(
                                              color: const Color(0xFF30D158),
                                              icon: Icons.check_rounded,
                                            ),
                                            title: 'Biquote live feed',
                                            numText: 'MT5',
                                          ),

                                          // Divider
                                          Container(
                                            height: 1,
                                            color: Colors.white.withValues(
                                              alpha: 0.08,
                                            ),
                                          ),

                                          // Row 3: Restoring Alerts -> Armed
                                          _buildStatusRow(
                                            dotWidget: _alertsResolved
                                                ? _buildDot(
                                                    color: const Color(
                                                      0xFF30D158,
                                                    ),
                                                    icon: Icons.check_rounded,
                                                  )
                                                : _buildSpinningDot(),
                                            title: _alertsResolved
                                                ? 'Restoring $alertCount alerts'
                                                : 'Loading saved alerts',
                                            numText: _alertsResolved
                                                ? 'Ready'
                                                : '…',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            const SplashSponsorAd(),

                            const Spacer(flex: 3),

                            // Bottom Section: Progress Bar & Footer
                            FadeTransition(
                              opacity: _fadeAnimation,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Animated Progress Bar (200px width, 4px height)
                                  Container(
                                    width: 200,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                    alignment: Alignment.centerLeft,
                                    child: AnimatedBuilder(
                                      animation: _progressAnimation,
                                      builder: (context, _) {
                                        return Container(
                                          width:
                                              200 *
                                              _progressAnimation.value.clamp(
                                                0.0,
                                                1.0,
                                              ),
                                          height: 4,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              2,
                                            ),
                                            gradient: const LinearGradient(
                                              colors: [
                                                Color(0xFF0A84FF),
                                                Color(0xFF64D2FF),
                                              ],
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFF0A84FF)
                                                    .withValues(alpha: 0.60),
                                                blurRadius: 8,
                                                offset: const Offset(0, 1),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 18),

                                  // Tagline (exact match Splash.dc.html line 44)
                                  Text(
                                    'Zero synthetic data · Live broker prices only',
                                    textAlign: TextAlign.center,
                                    style: AppTheme.sans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      color: const Color.fromRGBO(
                                        235,
                                        235,
                                        245,
                                        0.45,
                                      ),
                                      letterSpacing: -0.12,
                                    ),
                                  ),
                                  const SizedBox(height: 6),

                                  // Version (exact match Splash.dc.html line 45)
                                  Text(
                                    'v1.0.0',
                                    textAlign: TextAlign.center,
                                    style: AppTheme.mono(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w400,
                                      color: const Color.fromRGBO(
                                        235,
                                        235,
                                        245,
                                        0.30,
                                      ),
                                      letterSpacing: -0.22,
                                    ),
                                  ),
                                  const SizedBox(height: 36),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow({
    required Widget dotWidget,
    required String title,
    required String numText,
  }) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          dotWidget,
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: AppTheme.sans(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.white,
                letterSpacing: -0.15,
              ),
            ),
          ),
          Text(
            numText,
            style: AppTheme.mono(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: const Color.fromRGBO(235, 235, 245, 0.50),
              letterSpacing: -0.24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot({required Color color, required IconData icon}) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(icon, size: 14, color: Colors.black, weight: 800),
    );
  }

  Widget _buildSpinningDot() {
    return SizedBox(
      width: 24,
      height: 24,
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          backgroundColor: const Color(0xFF0A84FF).withValues(alpha: 0.25),
          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0A84FF)),
        ),
      ),
    );
  }
}
