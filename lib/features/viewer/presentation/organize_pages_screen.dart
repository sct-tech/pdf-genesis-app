import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../documents/data/pdf_file_store.dart';
import '../application/page_arrangement.dart';
import '../application/pdf_save_service.dart';
import 'widgets/icon_label_button.dart';

/// Reorder, rotate, duplicate, delete and add pages. Pops the saved
/// [LocalPdf], or null when closed without saving.
class OrganizePagesScreen extends ConsumerStatefulWidget {
  const OrganizePagesScreen({
    super.key,
    required this.documentId,
    required this.source,
  });

  final String documentId;
  final LocalPdf source;

  @override
  ConsumerState<OrganizePagesScreen> createState() =>
      _OrganizePagesScreenState();
}

class _OrganizePagesScreenState extends ConsumerState<OrganizePagesScreen> {
  // How close to the top or bottom edge a dragged page starts scrolling the
  // grid, and how far each tick moves it
  static const _scrollZone = 96.0;
  static const _scrollStep = 14.0;

  final _scroll = ScrollController();
  final _gridKey = GlobalKey();

  PdfDocument? _document;
  PageArrangement<PdfPage>? _arrangement;

  /// PDFs opened with "Add PDF". Their pages are only copied on save, so
  /// they stay open until this screen closes.
  final _added = <PdfDocument>[];
  Timer? _autoScroll;
  bool _loadFailed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _autoScroll?.cancel();
    _scroll.dispose();
    _document?.dispose();
    for (final document in _added) {
      document.dispose();
    }
    super.dispose();
  }

  Future<void> _open() async {
    try {
      await pdfrxFlutterInitialize();
      final document = await PdfDocument.openFile(widget.source.path);
      if (!mounted) return await document.dispose();
      setState(() {
        _document = document;
        _arrangement = PageArrangement(
          document.pages,
          maxPages: AppConfig.maxPdfPages,
          rotate: (page) => page.rotatedCW90(),
        );
      });
    } on Object {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  void _tooManyPages() {
    showAppSnackBar(
      context,
      'A PDF can have up to ${AppConfig.maxPdfPages} pages.',
    );
  }

  void _duplicate(PageArrangement<PdfPage> arrangement) {
    final done = arrangement.duplicateSelected();
    setState(() {});
    if (!done) _tooManyPages();
  }

  void _delete(PageArrangement<PdfPage> arrangement) {
    final done = arrangement.deleteSelected();
    setState(() {});
    if (!done) showAppSnackBar(context, 'A PDF needs at least one page.');
  }

  Future<void> _addPdf(PageArrangement<PdfPage> arrangement) async {
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
    } on Object {
      if (mounted) showAppSnackBar(context, 'Could not open the file picker.');
      return;
    }
    if (picked.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      final file = picked.first;
      final bytes = BytesBuilder(copy: false);
      await file.readAsByteStream().forEach(bytes.add);
      final document = await PdfDocument.openData(
        bytes.takeBytes(),
        // Unique per pick: the same file can be added twice
        sourceName: 'added:${_added.length}:${file.name}',
      );
      if (!mounted) return await document.dispose();
      if (!arrangement.append(document.pages)) {
        await document.dispose();
        if (mounted) _tooManyPages();
        return;
      }
      _added.add(document);
    } on Object {
      if (mounted) {
        showAppSnackBar(
          context,
          'That file could not be opened. It may be damaged or '
          'password protected.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(PageArrangement<PdfPage> arrangement) async {
    final saver = ref.read(pdfSaveServiceProvider);
    setState(() => _busy = true);
    try {
      final saved = await saver.savePages(
        documentId: widget.documentId,
        pages: arrangement.pages,
      );
      if (mounted) Navigator.of(context).pop(saved);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppSnackBar(context, errorMessage(error));
    }
  }

  Future<void> _close() async {
    if (_arrangement?.isChanged ?? false) {
      final discard = await confirmDestructive(
        context,
        title: 'Discard changes?',
        message: 'Your page changes have not been saved.',
        confirmLabel: 'Discard',
      );
      if (!discard || !mounted) return;
    }
    Navigator.of(context).pop();
  }

  /// Scrolls the grid while a dragged page is held near its top or bottom
  /// edge, so a page can be moved further than one screen.
  void _onDragUpdate(DragUpdateDetails details) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final y = box.globalToLocal(details.globalPosition).dy;
    final direction = y < _scrollZone
        ? -1
        : y > box.size.height - _scrollZone
        ? 1
        : 0;

    _autoScroll?.cancel();
    if (direction == 0) return;
    _autoScroll = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      final target = (position.pixels + direction * _scrollStep).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (target == position.pixels) return _autoScroll?.cancel();
      _scroll.jumpTo(target);
    });
  }

  void _onDragEnd() => _autoScroll?.cancel();

  Widget _grid(PageArrangement<PdfPage> arrangement) {
    final entries = arrangement.entries;
    return GridView.builder(
      key: _gridKey,
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      // Three columns on a phone, more as the window widens
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 170,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.68,
      ),
      itemCount: entries.length + 1,
      itemBuilder: (context, index) {
        if (index == entries.length) {
          return _AddTile(onTap: () => _addPdf(arrangement));
        }
        final entry = entries[index];
        return _PageTile(
          key: ValueKey(entry.id),
          entry: entry,
          number: index + 1,
          selected: arrangement.isSelected(entry.id),
          onTap: () => setState(() => arrangement.toggle(entry.id)),
          onDropped: (id) =>
              setState(() => arrangement.move(id, targetId: entry.id)),
          onDragUpdate: _onDragUpdate,
          onDragEnd: _onDragEnd,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final arrangement = _arrangement;
    final hasSelection = arrangement?.hasSelection ?? false;
    final changed = arrangement?.isChanged ?? false;
    final count = arrangement?.length ?? 0;

    VoidCallback? whenSelected(void Function(PageArrangement<PdfPage>) run) =>
        arrangement != null && hasSelection && !_busy
        ? () => run(arrangement)
        : null;

    return PopScope(
      canPop: !changed && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close',
            onPressed: _busy ? null : _close,
            icon: const Icon(Icons.close_rounded),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Organise pages'),
              if (arrangement != null)
                Text(
                  hasSelection
                      ? '${arrangement.selectedCount} selected'
                      : '$count ${count == 1 ? 'page' : 'pages'}',
                  style: text.bodySmall,
                ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(72, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onPressed: arrangement != null && changed && !_busy
                    ? () => _save(arrangement)
                    : null,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
        body: Stack(
          children: [
            if (_loadFailed)
              MessageView.error(
                message: 'This PDF could not be opened for editing.',
                onRetry: () {
                  setState(() => _loadFailed = false);
                  _open();
                },
              )
            else if (arrangement == null)
              const LoadingView()
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Text(
                      'Tap to select. Hold and drag a page to move it.',
                      style: text.bodySmall,
                    ),
                  ),
                  Expanded(child: _grid(arrangement)),
                ],
              ),
            if (_busy) const BusyOverlay(label: 'Please wait…'),
          ],
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: IconLabelButton(
                      icon: Icons.rotate_right_rounded,
                      label: 'Rotate',
                      onTap: whenSelected(
                        (pages) => setState(pages.rotateSelected),
                      ),
                    ),
                  ),
                  Expanded(
                    child: IconLabelButton(
                      icon: Icons.copy_rounded,
                      label: 'Duplicate',
                      onTap: whenSelected(_duplicate),
                    ),
                  ),
                  Expanded(
                    child: IconLabelButton(
                      icon: Icons.note_add_outlined,
                      label: 'Add PDF',
                      onTap: arrangement != null && !_busy
                          ? () => _addPdf(arrangement)
                          : null,
                    ),
                  ),
                  Expanded(
                    child: IconLabelButton(
                      icon: Icons.delete_outline_rounded,
                      label: 'Delete',
                      color: AppColors.danger,
                      onTap: whenSelected(_delete),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageTile extends StatelessWidget {
  const _PageTile({
    super.key,
    required this.entry,
    required this.number,
    required this.selected,
    required this.onTap,
    required this.onDropped,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final PageEntry<PdfPage> entry;
  final int number;
  final bool selected;
  final VoidCallback onTap;

  /// Called with the id of the tile that was dropped onto this one.
  final ValueChanged<int> onDropped;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final VoidCallback onDragEnd;

  Widget _sheet({bool highlighted = false}) {
    final page = entry.page;
    final outlined = selected || highlighted;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: outlined ? AppColors.primary : AppColors.border,
          width: outlined ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(4),
      child: PdfPageView(
        document: page.document,
        pageNumber: page.pageNumber,
        rotationOverride: page.rotation,
        maximumDpi: 72,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != entry.id,
      onAcceptWithDetails: (details) => onDropped(details.data),
      builder: (context, candidates, _) => LongPressDraggable<int>(
        data: entry.id,
        onDragUpdate: onDragUpdate,
        onDragEnd: (_) => onDragEnd(),
        onDraggableCanceled: (_, _) => onDragEnd(),
        feedback: SizedBox(
          width: 96,
          height: 128,
          child: Opacity(opacity: 0.9, child: _sheet(highlighted: true)),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: _sheet()),
        child: Semantics(
          button: true,
          selected: selected,
          label: 'Page $number',
          child: GestureDetector(
            onTap: onTap,
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: _sheet(highlighted: candidates.isNotEmpty),
                      ),
                      if (selected)
                        const Positioned(
                          top: 4,
                          right: 4,
                          child: CircleAvatar(
                            radius: 10,
                            backgroundColor: AppColors.primary,
                            child: Icon(
                              Icons.check_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$number',
                  style: text.labelMedium?.copyWith(
                    color: selected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Expanded(
          child: Material(
            color: AppColors.primaryTint,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: AppColors.primary),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_rounded, color: AppColors.primary),
                    const SizedBox(height: 2),
                    Text(
                      'Add PDF',
                      style: text.labelSmall?.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Keeps the tile the same height as the numbered page tiles
        Text('', style: text.labelMedium),
      ],
    );
  }
}
