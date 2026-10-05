import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/analytics_service.dart';
import '../data/app_user.dart';
import '../data/auth_repository.dart';

enum GoogleSignInOutcome {
  /// The user closed the Google account picker.
  cancelled,

  /// Signed in to a Google account.
  signedIn,

  /// The guest session became the Google account, keeping its documents.
  guestUpgraded,
}

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

  Future<void> continueAsGuest() async {
    final user = await _repository.continueAsGuest();
    ref.read(analyticsProvider).logEvent('login', {'method': 'guest'});
    state = AsyncData(_signedIn(user));
  }

  Future<GoogleSignInOutcome> signInWithGoogle() async {
    final guest = state.value;
    final wasGuest = guest?.isGuest ?? false;
    final user = await _repository.signInWithGoogle(carryOverGuest: wasGuest);
    if (user == null) return GoogleSignInOutcome.cancelled;
    ref.read(analyticsProvider).logEvent('login', {'method': 'google'});
    state = AsyncData(_signedIn(user));
    // The API upgrades the guest row in place, so the id survives. A Google
    // account that already existed keeps its own id and its own documents.
    return wasGuest && user.id == guest?.id
        ? GoogleSignInOutcome.guestUpgraded
        : GoogleSignInOutcome.signedIn;
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
  // Re-fetch when the account changes (guest to Google, sign-out)
  ref.watch(currentUserProvider.select((user) => user?.id));
  return ref.watch(authRepositoryProvider).fetchUsage();
});
