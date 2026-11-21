import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';

import '../services/alert_manager.dart';
import '../services/biquote_service.dart';
import '../services/settings_provider.dart';
import '../services/storage_service.dart';
import '../services/strategy_catalog_service.dart';
import '../theme/app_theme.dart';
import 'splash_screen.dart';

class AuthenticatedApp extends StatefulWidget {
  final User user;
  const AuthenticatedApp({super.key, required this.user});

  @override
  State<AuthenticatedApp> createState() => _AuthenticatedAppState();
}

class _AuthenticatedAppState extends State<AuthenticatedApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  BiquoteService? _biquoteService;
  AlertManager? _alertManager;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initializeAccountApp();
  }

  Future<void> _initializeAccountApp() async {
    await StrategyCatalogService.instance.initialize(widget.user.uid);
    await FirebaseCrashlytics.instance.setUserIdentifier(widget.user.uid);
    await SettingsProvider().loadAll();
    if (!mounted) return;
    _biquoteService = BiquoteService();
    _alertManager = AlertManager();
    setState(() => _loading = false);
    StorageService.onCloudSyncApplied = _refreshFromCloud;
    unawaited(_syncCloudInBackground());
  }

  Future<void> _syncCloudInBackground() async {
    await StorageService.syncAccountWithCloud(
      email: widget.user.email,
      displayName: widget.user.displayName,
    );
  }

  Future<void> _refreshFromCloud() async {
    if (!mounted) return;
    await SettingsProvider().loadAll();
    await _alertManager?.reloadFromStorage();
  }

  void _toggleTheme() => setState(() {
    _themeMode = _themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
  });

  @override
  void dispose() {
    unawaited(StrategyCatalogService.instance.stop());
    unawaited(FirebaseCrashlytics.instance.setUserIdentifier(''));
    StorageService.onCloudSyncApplied = null;
    _alertManager?.stopForAccountSignOut();
    _alertManager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TenX',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      navigatorObservers: [FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance)],
      home: _loading
          ? const Scaffold(
              backgroundColor: Colors.black,
              body: Center(child: CircularProgressIndicator()),
            )
          : SplashScreen(
              biquoteService: _biquoteService!,
              alertManager: _alertManager!,
              isDark: _themeMode == ThemeMode.dark,
              onToggleTheme: _toggleTheme,
              user: widget.user,
            ),
    );
  }
}
