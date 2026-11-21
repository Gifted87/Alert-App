import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Privacy-conscious app usage events and non-fatal diagnostics.
/// Never send symbols, prices, prompts, user email addresses, or API errors.
abstract final class AppTelemetry {
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  static bool get _firebaseReady => Firebase.apps.isNotEmpty;

  static Future<void> logScreen(String screenName) async {
    if (!_firebaseReady) return;
    try {
      await _analytics.logScreenView(screenName: screenName);
    } catch (_) {}
  }

  static Future<void> logAnalysisStarted({
    required String strategyId,
    required int specialistCount,
    required int timeframeCount,
  }) async {
    if (!_firebaseReady) return;
    try {
      await _analytics.logEvent(
        name: 'analysis_started',
        parameters: {
          'strategy_id': _safeId(strategyId),
          'specialist_count': specialistCount,
          'timeframe_count': timeframeCount,
        },
      );
    } catch (_) {}
  }

  static Future<void> logAnalysisCompleted({
    required String strategyId,
    required int elapsedMs,
  }) async {
    if (!_firebaseReady) return;
    try {
      await _analytics.logEvent(
        name: 'analysis_completed',
        parameters: {
          'strategy_id': _safeId(strategyId),
          'duration_ms': elapsedMs.clamp(0, 600000),
        },
      );
    } catch (_) {}
  }

  static Future<void> logAnalysisFailed({
    required String strategyId,
    required String errorCategory,
    required StackTrace stackTrace,
  }) async {
    if (_firebaseReady) {
      try {
        await _analytics.logEvent(
          name: 'analysis_failed',
          parameters: {
            'strategy_id': _safeId(strategyId),
            'error_category': _safeId(errorCategory),
          },
        );
        await FirebaseCrashlytics.instance.setCustomKey(
          'last_error_area',
          'analysis',
        );
        // Use a constant message so provider response bodies and prompt content
        // aren't copied into crash reports.
        await FirebaseCrashlytics.instance.recordError(
          StateError('AI analysis pipeline failed'),
          stackTrace,
          reason: 'AI analysis pipeline failed',
        );
      } catch (_) {}
    }
  }

  static Future<void> logAlertCreated({
    required String alertType,
    required int activeCount,
  }) async {
    if (!_firebaseReady) return;
    try {
      await _analytics.logEvent(
        name: 'alert_created',
        parameters: {
          'alert_type': _safeId(alertType),
          'active_count': activeCount,
        },
      );
    } catch (_) {}
  }

  static Future<void> logAlertChanged({
    required bool enabled,
    required int activeCount,
  }) async {
    if (!_firebaseReady) return;
    try {
      await _analytics.logEvent(
        name: enabled ? 'alert_enabled' : 'alert_disabled',
        parameters: {'active_count': activeCount},
      );
    } catch (_) {}
  }

  static Future<void> logAlertDeleted({required int activeCount}) async {
    if (!_firebaseReady) return;
    try {
      await _analytics.logEvent(
        name: 'alert_deleted',
        parameters: {'active_count': activeCount},
      );
    } catch (_) {}
  }

  static String _safeId(String input) {
    final value = input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
    return value.substring(0, value.length.clamp(0, 40));
  }
}
