import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../auth/application/auth_controller.dart';
import '../../chat/data/chat_repository.dart';
import '../../documents/application/document_actions.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _busy = false;

  /// Runs a destructive action behind a confirmation, with one at a time.
  Future<void> _confirmAndRun({
    required String title,
    required String message,
    required String confirmLabel,
    required Future<void> Function() action,
    String? doneMessage,
  }) async {
    final confirmed = await confirmDestructive(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await action();
      if (mounted && doneMessage != null) showAppSnackBar(context, doneMessage);
    } catch (error) {
      if (mounted) showAppSnackBar(context, errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _deleteAllDocuments() => _confirmAndRun(
    title: 'Delete all documents?',
    message: 'Every PDF, summary and conversation will be removed permanently.',
    confirmLabel: 'Delete all',
    doneMessage: 'All documents deleted',
    action: ref.read(documentActionsProvider).deleteAll,
  );

  void _clearChats() => _confirmAndRun(
    title: 'Clear chat history?',
    message: 'All conversations will be removed. Your PDFs and summaries stay.',
    confirmLabel: 'Clear',
    doneMessage: 'Chat history cleared',
    action: () => ref.read(chatRepositoryProvider).clearAll(),
  );

  void _deleteAccount() => _confirmAndRun(
    title: 'Delete account?',
    message:
        'Your account, PDFs and conversations will be deleted permanently. '
        'This cannot be undone.',
    confirmLabel: 'Delete account',
    // The router sends the user to login once the session is gone
    action: ref.read(authControllerProvider.notifier).deleteAccount,
  );

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const Scaffold(body: LoadingView());

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ContentWidth(
        child: AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              const _SectionLabel('ACCOUNT'),
              AppCard(
                padding: EdgeInsets.zero,
                child: _Row(label: 'Signed in as', value: user.email ?? '-'),
              ),
              const _SectionLabel('DATA'),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _Row(
                      label: 'Delete all documents',
                      chevron: true,
                      onTap: _deleteAllDocuments,
                    ),
                    const Divider(),
                    _Row(
                      label: 'Clear chat history',
                      chevron: true,
                      onTap: _clearChats,
                    ),
                  ],
                ),
              ),
              const _SectionLabel('ABOUT'),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _Row(
                      label: 'Privacy Policy',
                      chevron: true,
                      onTap: () =>
                          openExternalUrl(context, AppConfig.privacyPolicyUrl),
                    ),
                    const Divider(),
                    _Row(
                      label: 'Terms of Service',
                      chevron: true,
                      onTap: () => openExternalUrl(context, AppConfig.termsUrl),
                    ),
                    const Divider(),
                    const _Row(label: 'Version', value: AppConfig.version),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: _deleteAccount,
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                child: const Text('Delete account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    this.value,
    this.chevron = false,
    this.onTap,
  });

  final String label;
  final String? value;
  final bool chevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            // A row with no value gives the whole width to its label
            if (value == null)
              Expanded(child: Text(label, style: text.bodyLarge))
            else ...[
              Text(label, style: text.bodyLarge),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value!,
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            if (chevron)
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSubtle,
              ),
          ],
        ),
      ),
    );
  }
}
