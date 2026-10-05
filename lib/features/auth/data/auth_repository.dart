import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/token_storage.dart';
import 'app_user.dart';

class AuthRepository {
  AuthRepository(this._api, this._tokens);

  final ApiClient _api;
  final TokenStorage _tokens;

  bool _googleReady = false;

  Future<bool> get hasSession async => (await _tokens.accessToken) != null;

  Future<AppUser> _storeSession(dynamic data) async {
    final json = data as Map<String, dynamic>;
    await _tokens.save(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
    );
    return AppUser.fromJson(json['user'] as Map<String, dynamic>);
  }

  Future<AppUser> fetchCurrentUser() async {
    final data = await _api.get('/users/me');
    return AppUser.fromJson(data as Map<String, dynamic>);
  }

  Future<Usage> fetchUsage() async {
    final data = await _api.get('/users/me/usage');
    return Usage.fromJson(data as Map<String, dynamic>);
  }

  /// Runs Google Sign-In and exchanges the ID token for a session.
  /// Returns null when the user dismisses the account picker.
  Future<AppUser?> signInWithGoogle() async {
    final google = GoogleSignIn.instance;
    if (!_googleReady) {
      await google.initialize(
        serverClientId: AppConfig.googleServerClientId.isEmpty
            ? null
            : AppConfig.googleServerClientId,
      );
      _googleReady = true;
    }

    final GoogleSignInAccount account;
    try {
      account = await google.authenticate();
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return null;
      throw const ApiException(
        message: 'Google sign-in failed. Please try again.',
        name: 'GoogleSignInFailed',
      );
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const ApiException(
        message: 'Google sign-in failed. Please try again.',
        name: 'GoogleSignInFailed',
      );
    }

    return _storeSession(
      await _api.post('/auth/google', body: {'idToken': idToken}),
    );
  }

  Future<void> signOut() async {
    await _tokens.clear();
    if (_googleReady) {
      // Best effort: local sign-out already happened
      await GoogleSignIn.instance.signOut().catchError((_) {});
    }
  }

  Future<void> deleteAccount() async {
    await _api.delete('/users/me');
    await signOut();
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(tokenStorageProvider),
  ),
);
