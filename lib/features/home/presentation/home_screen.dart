import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/router/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/ads_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../auth/application/auth_controller.dart';
import '../../documents/data/document.dart';
import '../../documents/data/documents_repository.dart';
import '../../documents/presentation/document_widgets.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  /// Width of the body from which upload and recent documents sit side by
  /// side.
  static const _twoPaneWidth = 760.0;
  static const _introPaneWidth = 340.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final user = ref.watch(currentUserProvider);
    final documents = ref.watch(recentDocumentsProvider);
    final anyInProgress =
        documents.value?.any((document) => document.isInProgress) ?? false;
    final banner = ref.watch(adsProvider).banner(placement: 'home');

    final name = user == null ? '' : ', ${user.firstName}';

    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${greeting()}$name', style: text.headlineMedium),
        const SizedBox(height: 4),
        Text(
          'Upload a PDF and ask it anything.',
          style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        _UploadCard(onUpload: () => context.push(Routes.upload)),
      ],
    );

    final recent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Recent Documents', style: text.titleLarge)),
            if (documents.value?.isNotEmpty ?? false)
              TextButton(
                onPressed: () => context.go(Routes.documents),
                child: const Text('View all'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        documents.when(
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: LoadingView(),
          ),
          error: (error, _) => MessageView.error(
            message: errorMessage(error),
            onRetry: () => ref.invalidate(recentDocumentsProvider),
          ),
          data: (items) => items.isEmpty
              ? const AppCard(
                  padding: EdgeInsets.all(24),
                  child: MessageView(
                    icon: Icons.description_outlined,
                    title: 'No documents yet',
                    message: 'Your uploaded PDFs will appear here.',
                  ),
                )
              : AdaptiveGrid(
                  minItemWidth: 300,
                  children: [
                    for (final document in items)
                      _RecentDocumentCard(document: document),
                  ],
                ),
        ),
        if (banner != null) ...[const SizedBox(height: 8), banner],
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const AppLogo(size: 32),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                AppConfig.appName,
                style: text.titleLarge,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: PollWhile(
        active: anyInProgress,
        onTick: () => ref.invalidate(recentDocumentsProvider),
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(recentDocumentsProvider.future),
          child: ContentWidth(
            maxWidth: ContentWidths.wide,
            child: LayoutBuilder(
              builder: (context, constraints) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  // Side by side once there is room for both, stacked before
                  if (constraints.maxWidth >= _twoPaneWidth)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: _introPaneWidth, child: intro),
                        const SizedBox(width: 24),
                        Expanded(child: recent),
                      ],
                    )
                  else ...[
                    intro,
                    const SizedBox(height: 24),
                    recent,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UploadCard extends StatelessWidget {
  const _UploadCard({required this.onUpload});

  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.all(20),
      onTap: onUpload,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.cloud_upload_outlined,
              color: AppColors.primary,
              size: 30,
            ),
          ),
          const SizedBox(height: 14),
          Text('Add a document', style: text.titleLarge),
          const SizedBox(height: 4),
          Text(
            'PDF up to ${AppConfig.maxPdfSizeMb} MB and ${AppConfig.maxPdfPages} pages',
            style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onUpload,
            icon: const Icon(Icons.add_circle_outline_rounded),
            label: const Text('Upload PDF'),
          ),
        ],
      ),
    );
  }
}

class _RecentDocumentCard extends ConsumerWidget {
  const _RecentDocumentCard({required this.document});

  final Document document;

  void _open(BuildContext context) {
    context.push(
      document.isInProgress
          ? Routes.processing(document.id)
          : Routes.document(document.id),
    );
  }

  Future<void> _showMore(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('Open'),
              onTap: () => Navigator.of(context).pop('open'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('View & Edit PDF'),
              onTap: () => Navigator.of(context).pop('view'),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.danger,
              ),
              title: const Text(
                'Delete',
                style: TextStyle(color: AppColors.danger),
              ),
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'open') _open(context);
    if (action == 'view') context.push(Routes.viewer(document.id));
    if (action == 'delete') await deleteDocumentFlow(context, ref, document);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final ready = document.isReady;

    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () => _open(context),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              children: [
                const PdfTile(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        document.title,
                        style: text.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (document.pageCount != null)
                            formatPages(document.pageCount),
                          formatDate(document.createdAt),
                        ].join(' • '),
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(status: document.status),
              ],
            ),
          ),
          const Divider(),
          Row(
            children: [
              _QuickAction(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Chat',
                onTap: ready
                    ? () => context.push(Routes.chat(document.id))
                    : null,
              ),
              _QuickAction(
                icon: Icons.auto_awesome_outlined,
                label: 'Summary',
                onTap: ready
                    ? () => context.push(Routes.summary(document.id))
                    : null,
              ),
              _QuickAction(
                icon: Icons.more_horiz_rounded,
                label: 'More',
                onTap: () => _showMore(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null ? AppColors.textSubtle : AppColors.textPrimary;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
