import 'package:firebase_ui_auth/firebase_ui_auth.dart' as firebase_ui;
import 'package:firebase_ui_oauth_google/firebase_ui_oauth_google.dart';

abstract final class TenXAuthProviders {
  static final google = GoogleProvider(
    clientId: const String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID'),
    iOSPreferPlist: true,
  );

  static final emailPassword = firebase_ui.EmailAuthProvider();

  static final all = <firebase_ui.AuthProvider>[
    emailPassword,
    google,
  ];
}
