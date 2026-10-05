import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/router/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/app_user.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    // The router sends the user to login once the session is gone
    try {
      await ref.read(authControllerProvider.notifier).signOut();
    } catch (error) {
      if (context.mounted) showAppSnackBar(context, errorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final user = ref.watch(currentUserProvider);
    final usage = ref.watch(usageProvider);
    if (user == null) return const Scaffold(body: LoadingView());

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ContentWidth(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(usageProvider.future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              AppCard(
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.primaryTint,
                      foregroundImage: user.avatarUrl == null
                          ? null
                          : NetworkImage(user.avatarUrl!),
                      child: const Icon(
                        Icons.person_rounded,
                        color: AppColors.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.displayName,
                            style: text.titleLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            user.email ?? 'Not signed in',
                            style: text.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppCard(
                child: usage.when(
                  skipLoadingOnRefresh: true,
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: LoadingView(),
                  ),
                  error: (error, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Usage', style: text.titleLarge),
                      const SizedBox(height: 8),
                      Text(errorMessage(error), style: text.bodySmall),
                      TextButton(
                        onPressed: () => ref.invalidate(usageProvider),
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                  data: (usage) => _UsageBody(usage: usage),
                ),
              ),
              const SizedBox(height: 12),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _MenuRow(
                      icon: Icons.settings_outlined,
                      label: 'Settings',
                      onTap: () => context.push(Routes.settings),
                    ),
                    const Divider(indent: 56),
                    _MenuRow(
                      icon: Icons.shield_outlined,
                      label: 'Privacy Policy',
                      onTap: () =>
                          openExternalUrl(context, AppConfig.privacyPolicyUrl),
                    ),
                    const Divider(indent: 56),
                    _MenuRow(
                      icon: Icons.description_outlined,
                      label: 'Terms of Service',
                      onTap: () => openExternalUrl(context, AppConfig.termsUrl),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () => _signOut(context, ref),
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Sign out'),
              ),
              Center(
                child: Text(
                  '${AppConfig.appName} v${AppConfig.version}',
                  style: text.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UsageBody extends StatelessWidget {
  const _UsageBody({required this.usage});

  final Usage usage;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Usage', style: text.titleLarge),
        const SizedBox(height: 14),
        Row(
          children: [
            const Icon(
              Icons.picture_as_pdf_outlined,
              size: 20,
              color: AppColors.primary,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text('PDFs stored', style: text.bodyMedium)),
            Text(
              '${usage.documentsUsed} / ${usage.documentsLimit}',
              style: text.titleSmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: usage.documentsFraction,
            minHeight: 6,
            color: usage.atDocumentLimit ? AppColors.danger : AppColors.primary,
          ),
        ),
        if (usage.atDocumentLimit) ...[
          const SizedBox(height: 8),
          Text(
            'You have reached the limit. Delete a PDF to upload another.',
            style: text.bodySmall?.copyWith(color: AppColors.danger),
          ),
        ],
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 12),
        Text('Today', style: text.labelMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            _Counter(label: 'Uploads', value: usage.pdfUploadsToday),
            _Counter(label: 'Questions', value: usage.aiChatsToday),
            _Counter(label: 'Summaries', value: usage.summariesToday),
          ],
        ),
      ],
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', style: text.headlineSmall),
          Text(label, style: text.bodySmall),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: AppColors.textSecondary),
      title: Text(label, style: Theme.of(context).textTheme.bodyLarge),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.textSubtle,
      ),
    );
  }
}
