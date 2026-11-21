import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../config/api_config.dart';

/// Shared app settings. Firestore delivers updates to signed-in clients and
/// caches the last value locally; local defaults keep startup offline-first.
class AppRemoteConfig extends ChangeNotifier {
  AppRemoteConfig._();

  static final AppRemoteConfig instance = AppRemoteConfig._();

  final DateTime _appLaunchTime = DateTime.now();
  bool _toastBarDismissedThisLaunch = false;
  Duration get toastBarDelayRemaining =>
      const Duration(seconds: 30) - DateTime.now().difference(_appLaunchTime);
  bool get toastBarDismissedThisLaunch => _toastBarDismissedThisLaunch;
  void dismissToastBarForThisLaunch() => _toastBarDismissedThisLaunch = true;

  static const Map<String, Object> _defaults = {
    'llm_model': ApiConfig.llmModel,
    'llm_max_output_tokens': 8000,
    'llm_timeout_seconds': 120,
    'splash_ad_enabled': false,
    'splash_ad_image_url': '',
    'splash_ad_link_url': '',
    'splash_ad_campaign_id': '',
    'splash_ad_label': 'Sponsored',
    'toast_bar_enabled': false,
    'toast_bar_subject': '',
    'toast_bar_tagline': '',
    'toast_bar_link_url': '',
    'toast_bar_image_url': '',
  };

  Map<String, Object> _values = Map<String, Object>.from(_defaults);
  StreamSubscription<User?>? _authChanges;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _settingsChanges;
  bool _initialized = false;

  String get llmModel {
    final value = (_values['llm_model'] as String? ?? '').trim();
    return value.isEmpty ? ApiConfig.llmModel : value;
  }

  int get llmMaxOutputTokens =>
      (_values['llm_max_output_tokens'] as int? ?? 8000)
          .clamp(256, 32000)
          .toInt();

  int get llmTimeoutSeconds =>
      (_values['llm_timeout_seconds'] as int? ?? 120)
          .clamp(30, 300)
          .toInt();

  bool get splashAdEnabled => _values['splash_ad_enabled'] as bool? ?? false;

  String get splashAdImageUrl =>
      (_values['splash_ad_image_url'] as String? ?? '').trim();

  String get splashAdLinkUrl =>
      (_values['splash_ad_link_url'] as String? ?? '').trim();

  String get splashAdCampaignId =>
      (_values['splash_ad_campaign_id'] as String? ?? '').trim();

  String get splashAdLabel {
    final value = (_values['splash_ad_label'] as String? ?? '').trim();
    return value.isEmpty ? 'Sponsored' : value;
  }

  bool get toastBarEnabled => _values['toast_bar_enabled'] as bool? ?? false;

  String get toastBarSubject =>
      (_values['toast_bar_subject'] as String? ?? '').trim();

  String get toastBarTagline =>
      (_values['toast_bar_tagline'] as String? ?? '').trim();

  String get toastBarLinkUrl =>
      (_values['toast_bar_link_url'] as String? ?? '').trim();

  String get toastBarImageUrl =>
      (_values['toast_bar_image_url'] as String? ?? '').trim();

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _authChanges = FirebaseAuth.instance.authStateChanges().listen(
        _watchSettingsForUser,
        onError: (Object error) {
          debugPrint('App settings auth listener failed: $error');
        },
      );
    } catch (error) {
      debugPrint('App settings initialization failed; using local defaults: $error');
    }
  }

  Future<void> _watchSettingsForUser(User? user) async {
    await _settingsChanges?.cancel();
    _settingsChanges = null;
    if (user == null) {
      _values = Map<String, Object>.from(_defaults);
      notifyListeners();
      return;
    }

    _settingsChanges = FirebaseFirestore.instance
        .collection('appConfig')
        .doc('current')
        .snapshots()
        .listen(
      (snapshot) {
        final settings = snapshot.data()?['settings'];
        if (settings is Map<String, dynamic>) {
          final next = Map<String, Object>.from(_defaults);
          for (final key in _defaults.keys) {
            final value = settings[key];
            if (value.runtimeType == _defaults[key].runtimeType) {
              next[key] = value as Object;
            }
          }
          _values = next;
          notifyListeners();
        }
      },
      onError: (Object error) {
        // Retain cached settings and local defaults through connectivity/rules
        // errors so startup and alert handling never wait for the network.
        debugPrint('App settings sync failed; keeping cached values: $error');
      },
    );
  }

  Future<void> logSplashAdImpression() async {
    await _logSplashAdEvent('splash_ad_impression');
  }

  Future<void> logSplashAdClick() async {
    await _logSplashAdEvent('splash_ad_click');
  }

  Future<void> _logSplashAdEvent(String name) async {
    try {
      await FirebaseAnalytics.instance.logEvent(
        name: name,
        parameters: {
          if (splashAdCampaignId.isNotEmpty) 'campaign_id': splashAdCampaignId,
        },
      );
    } catch (error) {
      debugPrint('Unable to log $name: $error');
    }
  }

  @override
  void dispose() {
    _authChanges?.cancel();
    _settingsChanges?.cancel();
    super.dispose();
  }
}
