import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/router/routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../auth/application/auth_controller.dart';
import '../application/ai_limits.dart';
import '../data/document.dart';
import '../data/documents_repository.dart';
import 'document_widgets.dart';

/// Opens the PDF viewer and refreshes the document afterwards, since an
/// edit saved there can send it back to processing.
Future<void> openViewer(
  BuildContext context,
  WidgetRef ref,
  String documentId,
) async {
  await context.push(Routes.viewer(documentId));
  ref.invalidate(documentDetailProvider(documentId));
}

class DocumentDetailScreen extends ConsumerWidget {
  const DocumentDetailScreen({super.key, required this.documentId});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = ref.watch(documentDetailProvider(documentId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          document.value?.title ?? 'Document',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (document.hasValue)
            PopupMenuButton<String>(
              onSelected: (_) async {
                final deleted = await deleteDocumentFlow(
                  context,
                  ref,
                  document.value!,
                );
                if (deleted && context.mounted) context.pop();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Delete PDF',
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: ContentWidth(
        child: SafeArea(
          child: document.when(
            skipLoadingOnRefresh: true,
            skipLoadingOnReload: true,
            loading: () => const LoadingView(),
            error: (error, _) => MessageView.error(
              message: errorMessage(error),
              onRetry: () => ref.invalidate(documentDetailProvider(documentId)),
            ),
            data: (document) {
              if (!document.isReady) {
                return MessageView(
                  icon: document.isFailed
                      ? Icons.error_outline_rounded
                      : Icons.hourglass_top_rounded,
                  title: document.isFailed
                      ? 'Processing failed'
                      : 'Still processing',
                  message: document.isFailed
                      ? document.error
                      : 'This document is not ready yet.',
                  actionLabel: 'View progress',
                  onAction: () =>
                      context.pushReplacement(Routes.processing(document.id)),
                  secondaryLabel: 'View & Edit PDF',
                  onSecondary: () => openViewer(context, ref, document.id),
                );
              }
              return RefreshIndicator(
                onRefresh: () =>
                    ref.refresh(documentDetailProvider(documentId).future),
                child: _Body(document: document),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.document});

  final Document document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    // Opening this screen makes no AI request: the questions shown are the
    // ones stored once the document has been used with Ask AI
    final usage = ref.watch(usageProvider).value;
    final askAiBlocked = askAiBlockedReason(document, usage);
    final summaryBlocked = summaryBlockedReason(document, usage);

    // Coming back from chat should show the conversation just had
    Future<void> openChat({String? conversationId, String? question}) async {
      await context.push(
        Routes.chat(
          document.id,
          conversationId: conversationId,
          question: question,
        ),
      );
      ref.invalidate(documentDetailProvider(document.id));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PdfTile(size: 48),
                  const SizedBox(width: 12),
                  Expanded(child: Text(document.title, style: text.titleLarge)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _Meta(
                    icon: Icons.auto_stories_outlined,
                    label: 'Pages',
                    value: '${document.pageCount ?? '-'}',
                  ),
                  _Meta(
                    icon: Icons.sd_storage_outlined,
                    label: 'File size',
                    value: formatFileSize(document.fileSize),
                  ),
                  _Meta(
                    icon: Icons.event_outlined,
                    label: 'Uploaded',
                    value: formatDate(document.createdAt),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: askAiBlocked == null ? openChat : null,
          icon: const Icon(Icons.chat_bubble_outline_rounded),
          label: const Text('Ask Anything'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: summaryBlocked == null
              ? () => context.push(Routes.summary(document.id))
              : null,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: Text(
            document.hasSummary ? 'View Summary' : 'Generate Summary',
          ),
        ),
        if (summaryBlocked != null) ...[
          const SizedBox(height: 6),
          _LimitNote(text: summaryBlocked),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => openViewer(context, ref, document.id),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('View & Edit PDF'),
        ),
        if (document.suggestedQuestions.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Suggested questions', style: text.titleLarge),
          const SizedBox(height: 10),
          for (final question in document.suggestedQuestions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                onTap: askAiBlocked == null
                    ? () => openChat(question: question)
                    : null,
                child: Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(question, style: text.bodyMedium)),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textSubtle,
                    ),
                  ],
                ),
              ),
            ),
        ],
        if (document.recentConversations.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Recent conversations', style: text.titleLarge),
          const SizedBox(height: 10),
          for (final conversation in document.recentConversations)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                onTap: () => openChat(conversationId: conversation.id),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.title,
                            style: text.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatRelative(conversation.updatedAt),
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                    if (conversation.lastMessage != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        conversation.lastMessage!,
                        style: text.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(height: 4),
          Text(value, style: text.titleSmall, maxLines: 1),
          Text(label, style: text.bodySmall),
        ],
      ),
    );
  }
}

/// Explains, under a switched-off button, why it is off.
class _LimitNote extends StatelessWidget {
  const _LimitNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            Icons.schedule_rounded,
            size: 15,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
