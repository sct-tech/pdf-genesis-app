import 'package:flutter/foundation.dart';

/// Build-time configuration, overridable with `--dart-define`.
class AppConfig {
  const AppConfig._();

  /// Stops a release build that was made without its configuration: the
  /// default API address only exists on the Android emulator and is not
  /// encrypted.
  static void validate() {
    if (!kReleaseMode) return;
    if (!apiBaseUrl.startsWith('https://')) {
      throw StateError(
        'Release builds need --dart-define=API_BASE_URL=https://...',
      );
    }
    // Without it Google returns no ID token on Android and nobody can sign in
    if (googleServerClientId.isEmpty) {
      throw StateError(
        'Release builds need --dart-define=GOOGLE_SERVER_CLIENT_ID=...',
      );
    }
  }

  static const appName = 'PDF Genesis';
  static const tagline = 'Ask Anything From PDF';
  static const version = '1.0.0';

  static const productionApiBaseUrl =
      'https://pdf-genesis-backend.sct.technology';

  /// Release builds talk to production; debug builds to the local API at
  /// 10.0.2.2, the host machine as seen from the Android emulator.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: kReleaseMode ? productionApiBaseUrl : 'http://10.0.2.2:8190',
  );

  /// OAuth "Web application" client ID; the backend verifies ID tokens
  /// against it.
  static const googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  static const privacyPolicyUrl = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
    defaultValue: 'https://sct.technology/pdf-genesis/privacy',
  );

  static const termsUrl = String.fromEnvironment(
    'TERMS_URL',
    defaultValue: 'https://sct.technology/pdf-genesis/terms',
  );

  static const maxPdfSizeMb = 50;
  static const maxPdfBytes = maxPdfSizeMb * 1024 * 1024;
  static const maxPdfPages = 500;
}
