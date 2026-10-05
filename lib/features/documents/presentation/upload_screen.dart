import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/router/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../application/document_actions.dart';
import '../data/documents_repository.dart';

enum _UploadState { idle, selecting, uploading, failed, uploaded }

class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({super.key});

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  _UploadState _state = _UploadState.idle;
  double _progress = 0;
  String? _filename;
  int _fileSize = 0;
  String? _error;
  PlatformFile? _file;
  CancelToken? _cancelToken;

  bool get _busy =>
      _state == _UploadState.selecting || _state == _UploadState.uploading;

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  void _fail(String message) {
    setState(() {
      _state = _UploadState.failed;
      _error = message;
    });
  }

  Future<void> _select() async {
    setState(() {
      _state = _UploadState.selecting;
      _error = null;
    });

    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
    } catch (_) {
      if (mounted) _fail('Could not open the file picker.');
      return;
    }
    if (!mounted) return;

    if (picked.isEmpty) {
      setState(() => _state = _UploadState.idle);
      return;
    }

    final file = picked.first;
    final size = await file.length();
    if (!mounted) return;
    _filename = file.name;
    _fileSize = size ?? 0;
    _file = file;

    if (!file.name.toLowerCase().endsWith('.pdf')) {
      return _fail('Only PDF files are supported.');
    }
    if (size == null || size == 0) {
      return _fail('This file could not be read.');
    }
    if (size > AppConfig.maxPdfBytes) {
      return _fail(
        'This file is ${formatFileSize(size)}. '
        'The maximum is ${AppConfig.maxPdfSizeMb} MB.',
      );
    }
    await _upload();
  }

  Future<void> _upload() async {
    final file = _file;
    final filename = _filename;
    if (file == null || filename == null) return;

    setState(() {
      _state = _UploadState.uploading;
      _progress = 0;
      _error = null;
    });
    _cancelToken = CancelToken();
    // Taken before the first await: the upload finishes even if the user
    // leaves, and `ref` is unusable once this screen is gone
    final analytics = ref.read(analyticsProvider);
    final actions = ref.read(documentActionsProvider);

    try {
      final documentId = await ref
          .read(documentsRepositoryProvider)
          .upload(
            openRead: file.readAsByteStream,
            filename: filename,
            fileSize: _fileSize,
            cancelToken: _cancelToken,
            onProgress: (progress) {
              if (mounted) setState(() => _progress = progress);
            },
          );
      analytics.logEvent('pdf_upload', {'size': _fileSize});
      actions.refresh();
      if (!mounted) return;
      setState(() => _state = _UploadState.uploaded);
      context.pushReplacement(Routes.processing(documentId));
    } on DioException catch (error) {
      // Cancelled by leaving the screen: nothing to show
      if (!CancelToken.isCancel(error) && mounted) {
        _fail('Upload failed. Please try again.');
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.name == 'DocumentLimitReached') {
        setState(() => _state = _UploadState.idle);
        await _showLimitDialog(error.message);
      } else {
        _fail(error.message);
      }
    } on Object {
      // Anything unexpected must still release the screen from "uploading"
      if (mounted) _fail('Upload failed. Please try again.');
    }
  }

  Future<void> _showLimitDialog(String message) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PDF limit reached'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Upload PDF')),
      body: ContentWidth(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 32,
                ),
                onTap: _busy ? null : _select,
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.primaryTint,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.cloud_upload_outlined,
                        color: AppColors.primary,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Select PDF', style: text.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      'Tap to choose a file from your device',
                      style: text.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _busy ? null : _select,
                      icon: const Icon(Icons.folder_open_rounded),
                      label: Text(
                        _state == _UploadState.selecting
                            ? 'Opening…'
                            : 'Select PDF',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_filename != null && _state != _UploadState.idle) ...[
                _UploadStatusCard(
                  filename: _filename!,
                  fileSize: _fileSize,
                  state: _state,
                  progress: _progress,
                  error: _error,
                  onRetry:
                      _file == null ||
                          _fileSize == 0 ||
                          _fileSize > AppConfig.maxPdfBytes ||
                          !_filename!.toLowerCase().endsWith('.pdf')
                      ? null
                      : _upload,
                ),
                const SizedBox(height: 16),
              ] else if (_error != null) ...[
                Text(
                  _error!,
                  style: text.bodyMedium?.copyWith(color: AppColors.danger),
                ),
                const SizedBox(height: 16),
              ],
              const AppCard(
                child: Column(
                  children: [
                    _Rule(
                      icon: Icons.picture_as_pdf_outlined,
                      label: 'PDF files only',
                    ),
                    SizedBox(height: 12),
                    _Rule(
                      icon: Icons.sd_storage_outlined,
                      label: 'Maximum ${AppConfig.maxPdfSizeMb} MB',
                    ),
                    SizedBox(height: 12),
                    _Rule(
                      icon: Icons.auto_stories_outlined,
                      label: 'Maximum ${AppConfig.maxPdfPages} pages',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: 12),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _UploadStatusCard extends StatelessWidget {
  const _UploadStatusCard({
    required this.filename,
    required this.fileSize,
    required this.state,
    required this.progress,
    required this.error,
    required this.onRetry,
  });

  final String filename;
  final int fileSize;
  final _UploadState state;
  final double progress;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final failed = state == _UploadState.failed;
    final percent = (progress * 100).round();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PdfTile(size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      filename,
                      style: text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(formatFileSize(fileSize), style: text.bodySmall),
                  ],
                ),
              ),
              if (state == _UploadState.uploading)
                Text(
                  '$percent%',
                  style: text.titleSmall?.copyWith(color: AppColors.primary),
                ),
              if (state == _UploadState.uploaded)
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.success,
                ),
            ],
          ),
          if (state == _UploadState.uploading) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                // Indeterminate until the first bytes are acknowledged
                value: progress == 0 ? null : progress,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Text('Uploading document…', style: text.bodySmall),
          ],
          if (failed) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: AppColors.danger,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error ?? 'Upload failed',
                    style: text.bodyMedium?.copyWith(color: AppColors.danger),
                  ),
                ),
              ],
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onRetry,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
                child: const Text('Try again'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
