import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../data/report_repository.dart';

/// Lets the user flag an AI answer or summary as offensive, harmful or
/// wrong. Shows a thank-you once the report is sent.
Future<void> showReportSheet(BuildContext context, ReportTarget target) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _ReportSheet(target: target),
  );
  if ((sent ?? false) && context.mounted) {
    showAppSnackBar(context, 'Thanks. We will review this report.');
  }
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({required this.target});

  final ReportTarget target;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  final _details = TextEditingController();
  ReportReason? _reason;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(reportRepositoryProvider)
          .submit(widget.target, reason: reason, details: _details.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = errorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.target.title, style: text.titleLarge),
              const SizedBox(height: 4),
              Text(
                'What is wrong with this AI response?',
                style: text.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              RadioGroup<ReportReason>(
                groupValue: _reason,
                onChanged: (reason) {
                  if (_sending) return;
                  setState(() => _reason = reason);
                },
                child: Column(
                  children: [
                    for (final reason in ReportReason.values)
                      RadioListTile<ReportReason>(
                        value: reason,
                        title: Text(reason.label),
                        contentPadding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _details,
                enabled: !_sending,
                maxLength: ReportRepository.detailsMaxLength,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Add details (optional)',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _error!,
                  style: text.bodySmall?.copyWith(color: AppColors.danger),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _reason == null || _sending ? null : _submit,
                child: Text(_sending ? 'Sending…' : 'Send report'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
