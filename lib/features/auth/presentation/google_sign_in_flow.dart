import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/app_widgets.dart';
import '../application/auth_controller.dart';

/// Signs a guest in with Google from inside the app and reports the result
/// in a snackbar. Resolves to true when the user ends up signed in.
Future<bool> signInWithGoogleFlow(BuildContext context, WidgetRef ref) async {
  try {
    final outcome = await ref
        .read(authControllerProvider.notifier)
        .signInWithGoogle();
    if (!context.mounted) return outcome != GoogleSignInOutcome.cancelled;
    switch (outcome) {
      case GoogleSignInOutcome.guestUpgraded:
        showAppSnackBar(context, 'Signed in. Your documents are saved.');
      case GoogleSignInOutcome.signedIn:
        // An account that already existed: guest documents stay behind
        showAppSnackBar(context, 'Signed in to your existing account.');
      case GoogleSignInOutcome.cancelled:
        return false;
    }
    return true;
  } catch (error) {
    if (context.mounted) showAppSnackBar(context, errorMessage(error));
    return false;
  }
}
