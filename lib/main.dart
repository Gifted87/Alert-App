import 'dart:async';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart' as firebase_ui;
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'services/app_remote_config.dart';
import 'services/auth_providers.dart';
import 'screens/auth_gate.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (TenXFirebaseOptions.isConfigured) {
    await Firebase.initializeApp(options: TenXFirebaseOptions.currentPlatform);
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    ui.PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(FirebaseCrashlytics.instance.recordError(error, stack, fatal: true));
      return true;
    };
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );
    firebase_ui.FirebaseUIAuth.configureProviders(TenXAuthProviders.all);
    await AppRemoteConfig.instance.initialize();
  }
  runApp(const TenXApp());
}

class TenXApp extends StatelessWidget {
  const TenXApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TenX',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode: ThemeMode.dark,
    home: const AuthGate(),
  );
}
