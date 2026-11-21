import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Runtime Firebase configuration supplied with --dart-define values.
/// Replace this file with `flutterfire configure` output for production builds.
class TenXFirebaseOptions {
  // Android values are from the project's google-services.json. Keep Android
  // config in sync if Firebase Console issues a replacement file.
  static const _androidApiKey = 'AIzaSyAtFpQktmVereoFEMeuEmjqO_VvZgdGKYM';
  static const _androidAppId = '1:768885344354:android:6358b5c23f785655cbe93b';
  static const _androidSenderId = '768885344354';
  static const _androidProjectId = 'tenx-markets';
  static const _androidStorageBucket = 'tenx-markets.firebasestorage.app';
  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const _storageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
  static const _iosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');

  static bool get isConfigured => !kIsWeb && defaultTargetPlatform == TargetPlatform.android ||
      _apiKey.isNotEmpty && _appId.isNotEmpty && _senderId.isNotEmpty && _projectId.isNotEmpty;

  static FirebaseOptions? get currentPlatform {
    if (!isConfigured) return null;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return const FirebaseOptions(
        apiKey: _androidApiKey,
        appId: _androidAppId,
        messagingSenderId: _androidSenderId,
        projectId: _androidProjectId,
        storageBucket: _androidStorageBucket,
      );
    }
    return FirebaseOptions(
      apiKey: _apiKey,
      appId: _appId,
      messagingSenderId: _senderId,
      projectId: _projectId,
      authDomain: _authDomain.isEmpty ? null : _authDomain,
      storageBucket: _storageBucket.isEmpty ? null : _storageBucket,
      iosBundleId: defaultTargetPlatform == TargetPlatform.iOS ? _iosBundleId : null,
    );
  }
}
