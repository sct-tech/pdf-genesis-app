import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/analytics_service.dart';
import '../data/app_user.dart';
import '../data/auth_repository.dart';

/// The signed-in user, or null when signed out.
///
/// `build` restores the stored session on launch. It stays in the error state
/// only when the API cannot be reached, so the splash screen can offer a retry
/// without discarding a valid session.
class AuthController extends AsyncNotifier<AppUser?> {
  AuthRepository get _repository => ref.read(authRepositoryProvider);

  @override
  Future<AppUser?> build() async {
    final subscription = ref.watch(apiClientProvider).onSessionExpired.listen((
      _,
    ) {
      state = const AsyncData(null);
    });
    ref.onDispose(subscription.cancel);

    if (!await _repository.hasSession) return null;
    try {
      return _signedIn(await _repository.fetchCurrentUser());
    } on ApiException catch (error) {
      if (error.isUnauthorized) return null;
      rethrow;
    }
  }

  AppUser _signedIn(AppUser user) {
    ref.read(analyticsProvider).setUserId(user.id);
    return user;
  }

  /// Returns false when the user closed the Google account picker.
  Future<bool> signInWithGoogle() async {
    final user = await _repository.signInWithGoogle();
    if (user == null) return false;
    ref.read(analyticsProvider).logEvent('login', {'method': 'google'});
    state = AsyncData(_signedIn(user));
    return true;
  }

  Future<void> signOut() async {
    await _repository.signOut();
    ref.read(analyticsProvider).setUserId(null);
    state = const AsyncData(null);
  }

  Future<void> deleteAccount() async {
    await _repository.deleteAccount();
    ref.read(analyticsProvider).setUserId(null);
    state = const AsyncData(null);
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AppUser?>(
  AuthController.new,
);

/// The current user for screens that only render when signed in.
final currentUserProvider = Provider<AppUser?>(
  (ref) => ref.watch(authControllerProvider).value,
);

final usageProvider = FutureProvider.autoDispose<Usage>((ref) {
  // Re-fetch when the account changes (sign-out, another account)
  ref.watch(currentUserProvider.select((user) => user?.id));
  return ref.watch(authRepositoryProvider).fetchUsage();
});
