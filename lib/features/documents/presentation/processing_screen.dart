import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/router/routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../application/document_actions.dart';
import '../data/document.dart';
import '../data/documents_repository.dart';
import 'document_widgets.dart';

const _steps = [
  'Uploading document',
  'Reading pages',
  'Understanding content',
  'Preparing AI assistant',
  'Ready',
];

/// Index of the step currently running; `_steps.length` once all are done.
int _activeStep(Document document) {
  if (document.isReady) return _steps.length;
  return switch (document.stage) {
    'UNDERSTANDING_CONTENT' => 2,
    'PREPARING_ASSISTANT' => 3,
    // Queued or reading: the upload itself is already complete
    _ => 1,
  };
}

/// Follows a document through processing. Leaving is always allowed:
/// processing continues on the server and Home picks up the new status.
class ProcessingScreen extends ConsumerWidget {
  const ProcessingScreen({super.key, required this.documentId});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = ref.watch(documentDetailProvider(documentId));

    // Keep the lists in step when the status settles
    ref.listen(documentDetailProvider(documentId), (previous, next) {
      final was = previous?.value?.status;
      final now = next.value?.status;
      if (now != null && was != now && !next.value!.isInProgress) {
        ref.read(documentActionsProvider).refresh();
      }
    });
    final current = document.value;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.go(Routes.home),
        ),
        title: const Text('Processing'),
      ),
      body: ContentWidth(
        child: SafeArea(
          // The poller sits above the content so one failed poll neither
          // stops it nor replaces progress already on screen with an error
          child: PollWhile(
            active: current?.isInProgress ?? false,
            interval: const Duration(seconds: 2),
            onTick: () => ref.invalidate(documentDetailProvider(documentId)),
            child: switch (current) {
              final current? when current.isFailed => _Failed(
                document: current,
              ),
              final current? => _Progress(document: current),
              null when document.hasError => MessageView.error(
                message: errorMessage(document.error!),
                onRetry: () =>
                    ref.invalidate(documentDetailProvider(documentId)),
              ),
              null => const LoadingView(),
            },
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.document});

  final Document document;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final active = _activeStep(document);
    final ready = document.isReady;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppCard(
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
                    Text(documentMeta(document), style: text.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ready ? 'Your document is ready' : 'Analysing your document',
                style: text.titleLarge,
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: active / _steps.length,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 20),
              for (var i = 0; i < _steps.length; i++)
                _StepRow(
                  label: _steps[i],
                  done: i < active,
                  active: i == active,
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (ready)
          FilledButton(
            onPressed: () =>
                context.pushReplacement(Routes.document(document.id)),
            child: const Text('Open document'),
          )
        else ...[
          OutlinedButton(
            onPressed: () => context.go(Routes.home),
            child: const Text('Continue in background'),
          ),
          const SizedBox(height: 12),
          Text(
            'You can leave this screen. Processing continues and the '
            'document will show as Ready on Home.',
            style: text.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.done,
    required this.active,
  });

  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final Widget marker;
    if (done) {
      marker = const Icon(
        Icons.check_circle_rounded,
        color: AppColors.success,
        size: 22,
      );
    } else if (active) {
      marker = const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2.2),
      );
    } else {
      marker = const Icon(
        Icons.radio_button_unchecked_rounded,
        color: AppColors.textSubtle,
        size: 22,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 24, child: Center(child: marker)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: text.bodyLarge?.copyWith(
                color: done || active
                    ? AppColors.textPrimary
                    : AppColors.textSubtle,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Failed extends ConsumerStatefulWidget {
  const _Failed({required this.document});

  final Document document;

  @override
  ConsumerState<_Failed> createState() => _FailedState();
}

class _FailedState extends ConsumerState<_Failed> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    final actions = ref.read(documentActionsProvider);
    try {
      await ref.read(documentsRepositoryProvider).retry(widget.document.id);
      if (mounted) ref.invalidate(documentDetailProvider(widget.document.id));
      actions.refresh();
    } catch (error) {
      if (mounted) showAppSnackBar(context, errorMessage(error));
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  Future<void> _delete() async {
    final deleted = await deleteDocumentFlow(context, ref, widget.document);
    if (deleted && mounted) context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 24),
        const Icon(
          Icons.error_outline_rounded,
          color: AppColors.danger,
          size: 56,
        ),
        const SizedBox(height: 16),
        Text(
          'This PDF could not be processed',
          style: text.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          widget.document.error ?? 'Please try again.',
          style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: _retrying ? null : _retry,
          child: Text(_retrying ? 'Retrying…' : 'Try again'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _retrying ? null : _delete,
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
          child: const Text('Delete PDF'),
        ),
      ],
    );
  }
}
