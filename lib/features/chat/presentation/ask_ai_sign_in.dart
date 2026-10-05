import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../auth/presentation/google_sign_in_flow.dart';

const askAiSignInTitle = 'Sign in to use Ask AI';
const askAiSignInMessage =
    'Log in to get access to the PDF Genesis Ask AI feature and ask '
    'questions about your PDFs.';

/// Explains to a guest why Ask AI is locked and offers Google sign-in.
/// Resolves to true when the user signed in from the sheet.
Future<bool> showAskAiSignInSheet(BuildContext context, WidgetRef ref) async {
  final wantsSignIn = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final text = Theme.of(context).textTheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.primaryTint,
                child: Icon(
                  Icons.lock_outline_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                askAiSignInTitle,
                style: text.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                askAiSignInMessage,
                style: text.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Continue with Google'),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Not now'),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (wantsSignIn != true || !context.mounted) return false;
  return signInWithGoogleFlow(context, ref);
}

/// Inline hint shown where Ask AI would be, for a guest.
class AskAiSignInHint extends ConsumerWidget {
  const AskAiSignInHint({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Row(
        children: [
          const Icon(
            Icons.lock_outline_rounded,
            size: 20,
            color: AppColors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(askAiSignInMessage, style: text.bodySmall)),
          TextButton(
            onPressed: () => signInWithGoogleFlow(context, ref),
            child: const Text('Log in'),
          ),
        ],
      ),
    );
  }
}
