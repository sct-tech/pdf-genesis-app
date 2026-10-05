import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../data/document.dart';
import '../application/document_actions.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final ProcessingStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      ProcessingStatus.ready => const Pill(
        label: 'Ready',
        foreground: AppColors.success,
        background: AppColors.successTint,
      ),
      ProcessingStatus.failed => const Pill(
        label: 'Failed',
        foreground: AppColors.danger,
        background: AppColors.dangerTint,
      ),
      _ => const Pill(
        label: 'Processing',
        foreground: AppColors.primary,
        background: AppColors.primaryTint,
        leading: SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(strokeWidth: 1.6),
        ),
      ),
    };
  }
}

/// "32 pages • 8.4 MB • Oct 2, 2026", skipping parts not known yet.
String documentMeta(Document document) => [
  if (document.pageCount != null) formatPages(document.pageCount),
  if (document.fileSize > 0) formatFileSize(document.fileSize),
  formatDate(document.createdAt),
].join(' • ');

/// Confirms, deletes and refreshes the lists. Returns true when deleted.
Future<bool> deleteDocumentFlow(
  BuildContext context,
  WidgetRef ref,
  Document document,
) async {
  // Taken before the first await: the row that opened this may be gone by
  // the time the request finishes
  final actions = ref.read(documentActionsProvider);
  final confirmed = await confirmDestructive(
    context,
    title: 'Delete this PDF?',
    message:
        '"${document.title}" and its conversations will be removed permanently.',
  );
  if (!confirmed) return false;
  try {
    await actions.delete(document.id);
    if (context.mounted) showAppSnackBar(context, 'PDF deleted');
    return true;
  } catch (error) {
    if (context.mounted) showAppSnackBar(context, errorMessage(error));
    return false;
  }
}

/// Calls [onTick] every few seconds while [active] is true, so screens that
/// list documents pick up processing results without a manual refresh.
class PollWhile extends StatefulWidget {
  const PollWhile({
    super.key,
    required this.active,
    required this.onTick,
    required this.child,
    this.interval = const Duration(seconds: 4),
  });

  final bool active;
  final VoidCallback onTick;
  final Widget child;
  final Duration interval;

  @override
  State<PollWhile> createState() => _PollWhileState();
}

class _PollWhileState extends State<PollWhile> with WidgetsBindingObserver {
  Timer? _timer;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // No point asking the server for news nobody can see
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    _sync();
  }

  @override
  void didUpdateWidget(PollWhile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _sync();
  }

  void _sync() {
    _timer?.cancel();
    _timer = widget.active && _foreground
        ? Timer.periodic(widget.interval, (_) => widget.onTick())
        : null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
