import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small pieces of local state kept in SharedPreferences. Anything tied to
/// the signed-in person is cleared when the account on the device changes.
class AppPrefs {
  AppPrefs(this._prefs);

  static const _onboardingSeenKey = 'onboarding_seen';
  static const _signatureKey = 'saved_signature';

  final SharedPreferences _prefs;

  bool get onboardingSeen => _prefs.getBool(_onboardingSeenKey) ?? false;

  Future<void> setOnboardingSeen() => _prefs.setBool(_onboardingSeenKey, true);

  /// The last signature drawn in the PDF editor, as JSON.
  String? get signature => _prefs.getString(_signatureKey);

  Future<void> setSignature(String json) =>
      _prefs.setString(_signatureKey, json);

  Future<void> clearSignature() => _prefs.remove(_signatureKey);
}

/// Overridden in `main()` once SharedPreferences has loaded.
final appPrefsProvider = Provider<AppPrefs>(
  (ref) => throw UnimplementedError('appPrefsProvider must be overridden'),
);
