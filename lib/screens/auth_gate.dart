import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../firebase_options.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import 'authenticated_app.dart';
import 'sign_in_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _signInSplashComplete = false;
  User? _previousUser;
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (_previousUser != null && user == null && mounted) {
        setState(() => _signInSplashComplete = false);
      }
      _previousUser = user;
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!TenXFirebaseOptions.isConfigured) {
      return const _FirebaseSetupRequired();
    }
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _AuthLoading();
        }
        final user = snapshot.data;
        StorageService.userScope = user?.uid;
        if (user == null) {
          if (!_signInSplashComplete) {
            return _SignInLaunchSplash(
              onComplete: () {
                if (mounted) setState(() => _signInSplashComplete = true);
              },
            );
          }
          return const TenXSignInScreen();
        }
        return AuthenticatedApp(user: user);
      },
    );
  }
}

class _SignInLaunchSplash extends StatefulWidget {
  final VoidCallback onComplete;
  const _SignInLaunchSplash({required this.onComplete});

  @override
  State<_SignInLaunchSplash> createState() => _SignInLaunchSplashState();
}

class _SignInLaunchSplashState extends State<_SignInLaunchSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  Timer? _finishTimer;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..forward();
    _finishTimer = Timer(const Duration(milliseconds: 1450), widget.onComplete);
  }

  @override
  void dispose() {
    _finishTimer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      children: [
        Positioned(
          top: -120,
          left: -60,
          right: -60,
          height: 500,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                colors: [Color(0x4D0A84FF), Color(0x1264D2FF), Colors.transparent],
                stops: [0, .55, 1],
              ),
            ),
          ),
        ),
        Center(
          child: FadeTransition(
            opacity: CurvedAnimation(parent: _animation, curve: Curves.easeOut),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(29),
                    gradient: const LinearGradient(
                      colors: [AppTheme.darkPrimary, AppTheme.darkCyan],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.darkPrimary.withValues(alpha: .4),
                        blurRadius: 44,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(29),
                    child: Image.asset(
                      'assets/tenx_logo.png',
                      width: 92,
                      height: 92,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'TenX',
                  style: AppTheme.sans(fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: -1.6),
                ),
                const SizedBox(height: 5),
                Text(
                  'Alerts and Multi Agent Analysis',
                  style: AppTheme.sans(fontSize: 14, color: AppTheme.darkTextSecondary),
                ),
                const SizedBox(height: 28),
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.darkPrimary),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _AuthLoading extends StatelessWidget {
  const _AuthLoading();

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Colors.black,
    body: Center(child: CircularProgressIndicator()),
  );
}

class _FirebaseSetupRequired extends StatelessWidget {
  const _FirebaseSetupRequired();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                color: Color(0xFF64D2FF),
                size: 48,
              ),
              const SizedBox(height: 20),
              Text(
                'Connect Firebase to enable accounts',
                textAlign: TextAlign.center,
                style: AppTheme.sans(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Google and passwordless email sign-in are ready in the app. Add the Firebase project configuration and enable these providers in Firebase Console to continue.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
