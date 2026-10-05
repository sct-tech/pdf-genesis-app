import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../auth/application/auth_controller.dart';
import '../data/document.dart';
import '../data/documents_repository.dart';

class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({super.key, required this.documentId});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(documentSummaryProvider(documentId));

    // The detail screen's button reads "View Summary" once one exists
    ref.listen(documentSummaryProvider(documentId), (previous, next) {
      if (!(previous?.hasValue ?? false) && next.hasValue) {
        ref
          ..invalidate(documentDetailProvider(documentId))
          ..invalidate(usageProvider);
      }
    });

    final title =
        ref.watch(documentDetailProvider(documentId)).value?.title ?? 'Summary';

    return Scaffold(
      appBar: AppBar(title: const Text('Summary')),
      body: ContentWidth(
        child: SafeArea(
          child: summary.when(
            loading: () => const LoadingView(label: 'Generating summary…'),
            error: (error, _) =>
                error is ApiException && error.isFinalForToday
                ? MessageView(
                    icon: Icons.schedule_rounded,
                    title: error.isDailyLimit
                        ? 'Daily limit reached'
                        : 'Summary not available',
                    message: error.message,
                    actionLabel: 'Go back',
                    onAction: () => Navigator.of(context).maybePop(),
                  )
                : MessageView.error(
                    message: errorMessage(error),
                    onRetry: () =>
                        ref.invalidate(documentSummaryProvider(documentId)),
                  ),
            data: (summary) => _SummaryBody(title: title, summary: summary),
          ),
        ),
      ),
    );
  }
}

class _SummaryBody extends StatelessWidget {
  const _SummaryBody({required this.title, required this.summary});

  final String title;
  final DocumentSummary summary;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: summary.toPlainText(title)));
    if (context.mounted) showAppSnackBar(context, 'Summary copied');
  }

  Future<void> _share() => SharePlus.instance.share(
    ShareParams(text: summary.toPlainText(title), subject: title),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: [
              Text(title, style: text.headlineSmall),
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle(
                      icon: Icons.article_outlined,
                      label: 'Document Summary',
                    ),
                    const SizedBox(height: 10),
                    SelectableText(summary.summary, style: text.bodyLarge),
                  ],
                ),
              ),
              if (summary.keyPoints.isNotEmpty) ...[
                const SizedBox(height: 12),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionTitle(
                        icon: Icons.bolt_outlined,
                        label: 'Key Points',
                      ),
                      const SizedBox(height: 6),
                      for (final (index, point) in summary.keyPoints.indexed)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                alignment: Alignment.center,
                                decoration: const BoxDecoration(
                                  color: AppColors.primaryTint,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${index + 1}',
                                  style: text.labelSmall?.copyWith(
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(point, style: text.bodyMedium),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copy(context),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _share,
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: const Text('Share'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }
}
