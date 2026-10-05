import 'package:flutter/foundation.dart';

/// Build-time configuration, overridable with `--dart-define`.
class AppConfig {
  const AppConfig._();

  /// Stops a release build that was made without its configuration: the
  /// default API address only exists on the Android emulator and is not
  /// encrypted.
  static void validate() {
    if (kReleaseMode && !apiBaseUrl.startsWith('https://')) {
      throw StateError(
        'Release builds need --dart-define=API_BASE_URL=https://...',
      );
    }
  }

  static const appName = 'PDF Genesis';
  static const tagline = 'Ask Anything From PDF';
  static const version = '1.0.0';

  /// 10.0.2.2 is the host machine as seen from the Android emulator.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8190',
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

  static const freeMaxDocuments = 3;
  static const proMaxDocuments = 10;
}
