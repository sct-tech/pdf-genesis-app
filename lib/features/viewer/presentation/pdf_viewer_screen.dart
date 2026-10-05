import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../documents/data/document.dart';
import '../../documents/data/documents_repository.dart';
import '../../documents/data/pdf_file_store.dart';
import '../../documents/presentation/document_widgets.dart';
import '../application/edit_session.dart';
import '../application/pdf_save_service.dart';
import '../application/touch_tracker.dart';
import '../data/edit_marks.dart';
import 'edit_toolbars.dart';
import 'organize_pages_screen.dart';
import 'page_edit_layer.dart';
import 'signature_pad.dart';
import 'widgets/icon_label_button.dart';
import 'widgets/text_note_dialog.dart';
import 'widgets/viewer_action_bar.dart';

/// Reads a document's PDF and, in edit mode, draws on it.
class PdfViewerScreen extends ConsumerStatefulWidget {
  const PdfViewerScreen({super.key, required this.documentId});

  final String documentId;

  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen> {
  static const _canvasColor = Color(0xFFF1F5F9);

  final _controller = PdfViewerController();
  final _session = EditSession();
  final _touches = TouchTracker();
  final _searchField = TextEditingController();

  /// Created once the document is loaded; pdfrx cannot build it earlier.
  PdfTextSearcher? _searcher;

  /// Set after a save, when the file on screen is newer than the provider's.
  LocalPdf? _saved;
  Signature? _signature;
  EditTool? _tool;
  int? _pageNumber;
  int? _pageCount;
  bool _editing = false;
  bool _searching = false;
  bool _saving = false;

  String get _id => widget.documentId;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSessionChanged);
    _signature = ref.read(signatureStoreProvider).load();
  }

  @override
  void dispose() {
    _session
      ..removeListener(_onSessionChanged)
      ..dispose();
    _disposeSearcher();
    _searchField.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _disposeSearcher() {
    _searcher
      ?..removeListener(_rebuild)
      ..dispose();
    _searcher = null;
  }

  /// The viewer only needs rebuilding when the tool changes (one-finger
  /// scrolling is switched off while drawing); strokes repaint on their own.
  void _onSessionChanged() {
    if (_session.tool != _tool) setState(() => _tool = _session.tool);
  }

  // View mode

  Future<void> _share(LocalPdf local, String title) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(local.path, mimeType: 'application/pdf')],
          fileNameOverrides: ['$title.pdf'],
          subject: title,
        ),
      );
    } on Object {
      if (mounted) showAppSnackBar(context, 'This PDF could not be shared.');
    }
  }

  Future<void> _organise(LocalPdf local) async {
    final saved = await Navigator.of(context).push<LocalPdf>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) =>
            OrganizePagesScreen(documentId: _id, source: local),
      ),
    );
    if (saved == null || !mounted) return;
    setState(() => _saved = saved);
    _announceSave(reprocessed: true);
  }

  void _askAi(Document? document) {
    if (document == null || !document.isReady) {
      showAppSnackBar(
        context,
        (document?.isFailed ?? false)
            ? 'The assistant could not read this PDF, so it cannot answer '
                  'questions about it.'
            : 'The assistant is still reading this PDF. Try again shortly.',
      );
      return;
    }
    context.push(Routes.chat(_id));
  }

  void _closeSearch() {
    _searcher?.resetTextSearch();
    _searchField.clear();
    setState(() => _searching = false);
  }

  // Edit mode

  Future<void> _selectTool(EditTool tool) async {
    if (_session.tool == tool) {
      _session.tool = null;
      return;
    }
    if (tool == EditTool.sign && _signature == null) {
      await _newSignature();
      if (!mounted || _signature == null) return;
    }
    _session.tool = tool;
  }

  Future<void> _newSignature() async {
    final store = ref.read(signatureStoreProvider);
    final signature = await showSignaturePad(context);
    if (signature == null || !mounted) return;
    _signature = signature;
    showAppSnackBar(context, 'Tap the page where you want to sign.');
    await store.save(signature);
  }

  Future<void> _editText(
    int page,
    Offset position,
    double pageAspectRatio,
    TextMark? existing,
  ) async {
    final text = await showTextNoteDialog(
      context,
      initial: existing?.text ?? '',
    );
    if (text == null || !mounted) return;
    if (existing != null) {
      if (text.isEmpty) {
        _session.remove(existing);
      } else if (text != existing.text) {
        _session.replace(existing, existing.copyWith(text: text));
      }
    } else if (text.isNotEmpty) {
      _session.addText(page, position, text, pageAspectRatio);
    }
  }

  void _placeSignature(int page, Offset position, double pageAspectRatio) {
    final signature = _signature;
    if (signature == null) return;
    _session.addSignature(page, position, signature, pageAspectRatio);
  }

  void _leaveEditor() {
    _session
      ..clear()
      ..tool = null;
    setState(() => _editing = false);
  }

  /// Leaves edit mode, asking first when there are unsaved marks.
  Future<void> _closeEditor() async {
    if (_session.hasChanges) {
      final discard = await confirmDestructive(
        context,
        title: 'Discard changes?',
        message: 'Your edits to this PDF have not been saved.',
        confirmLabel: 'Discard',
      );
      if (!discard || !mounted) return;
    }
    _leaveEditor();
  }

  Future<void> _save(LocalPdf local) async {
    if (!_session.hasChanges) return _leaveEditor();
    final changesText = _session.changesText;
    final saver = ref.read(pdfSaveServiceProvider);
    setState(() => _saving = true);
    try {
      final saved = await saver.saveMarks(
        documentId: _id,
        source: local,
        marks: _session.marks,
        changesText: changesText,
      );
      if (!mounted) return;
      _saved = saved;
      _leaveEditor();
      _announceSave(reprocessed: changesText);
    } on Object catch (error) {
      // The marks stay in the session so nothing drawn is lost
      if (mounted) showAppSnackBar(context, errorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _announceSave({required bool reprocessed}) {
    showAppSnackBar(
      context,
      reprocessed
          ? 'Saved. The assistant is re-reading the updated PDF.'
          : 'Changes saved',
    );
  }

  PdfViewerParams _viewerParams() {
    return PdfViewerParams(
      backgroundColor: _canvasColor,
      margin: 10,
      // One finger draws while a tool is active; two fingers still zoom
      panEnabled: !(_editing && _tool != null),
      textSelectionParams: PdfTextSelectionParams(enabled: !_editing),
      onViewerReady: (document, controller) {
        // A saved edit opens a new document, which needs its own searcher
        _disposeSearcher();
        _searcher = PdfTextSearcher(controller)..addListener(_rebuild);
        setState(() {
          _pageCount = document.pages.length;
          _pageNumber = controller.pageNumber ?? 1;
        });
      },
      onPageChanged: (pageNumber) => setState(() => _pageNumber = pageNumber),
      pagePaintCallbacks: [
        (canvas, pageRect, page) =>
            _searcher?.pageTextMatchPaintCallback(canvas, pageRect, page),
      ],
      pageOverlaysBuilder: (context, pageRect, page) => [
        if (_editing)
          Positioned.fill(
            child: PageEditLayer(
              page: page.pageNumber,
              session: _session,
              touches: _touches,
              onTextRequested: _editText,
              onSignatureRequested: _placeSignature,
            ),
          ),
      ],
      viewerOverlayBuilder: (context, size, handleLinkTap) => [
        if (!_editing)
          PdfViewerScrollThumb(
            controller: _controller,
            thumbSize: const Size(6, 44),
            thumbBuilder: (context, thumbSize, pageNumber, controller) =>
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.textSubtle,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
          ),
      ],
    );
  }

  AppBar _editBar(LocalPdf? local) {
    return AppBar(
      leading: IconButton(
        tooltip: 'Close editor',
        onPressed: _saving ? null : _closeEditor,
        icon: const Icon(Icons.close_rounded),
      ),
      title: const Text('Edit PDF'),
      actions: [
        ListenableBuilder(
          listenable: _session,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Undo',
                onPressed: _session.canUndo && !_saving ? _session.undo : null,
                icon: const Icon(Icons.undo_rounded),
              ),
              IconButton(
                tooltip: 'Redo',
                onPressed: _session.canRedo && !_saving ? _session.redo : null,
                icon: const Icon(Icons.redo_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 12),
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(72, 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onPressed: _saving || local == null ? null : () => _save(local),
            child: const Text('Save'),
          ),
        ),
      ],
    );
  }

  AppBar _searchBar() {
    final searcher = _searcher;
    final matches = searcher?.matches.length ?? 0;
    final String status;
    if (matches > 0) {
      status = '${(searcher?.currentIndex ?? 0) + 1} of $matches';
    } else if (searcher?.isSearching ?? false) {
      status = '…';
    } else {
      status = 'No results';
    }

    return AppBar(
      leading: IconButton(
        tooltip: 'Close search',
        onPressed: _closeSearch,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      titleSpacing: 0,
      title: TextField(
        controller: _searchField,
        autofocus: true,
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(
          hintText: 'Search in this PDF',
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
        ),
        onChanged: (value) => searcher?.startTextSearch(value.trim()),
      ),
      actions: [
        if (_searchField.text.trim().isNotEmpty)
          Center(
            child: Text(status, style: Theme.of(context).textTheme.bodySmall),
          ),
        IconButton(
          tooltip: 'Previous result',
          onPressed: matches == 0 ? null : searcher?.goToPrevMatch,
          icon: const Icon(Icons.keyboard_arrow_up_rounded),
        ),
        IconButton(
          tooltip: 'Next result',
          onPressed: matches == 0 ? null : searcher?.goToNextMatch,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
        ),
      ],
    );
  }

  AppBar _viewBar(Document? document) {
    final pages = _pageCount ?? document?.pageCount;
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            document?.title ?? 'Document',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (document != null)
            Text(
              [
                if (pages != null) formatPages(pages),
                formatFileSize(document.fileSize),
              ].join(' • '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Search',
          onPressed: _searcher == null
              ? null
              : () => setState(() => _searching = true),
          icon: const Icon(Icons.search_rounded),
        ),
      ],
    );
  }

  Widget _viewer(LocalPdf local, Document? document) {
    final pageNumber = _pageNumber;
    final pageCount = _pageCount;
    return Stack(
      children: [
        Positioned.fill(
          child: PdfViewer.file(
            local.path,
            // A saved edit is a new file: start a fresh viewer for it
            key: ValueKey(local.path),
            controller: _controller,
            initialPageNumber: pageNumber ?? 1,
            params: _viewerParams(),
          ),
        ),
        if (pageNumber != null && pageCount != null)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: PageIndicator(page: pageNumber, count: pageCount),
            ),
          ),
        if (_editing)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: _saving,
              child: ContentWidth.bar(
                child: EditOptionsStrip(
                  session: _session,
                  onNewSignature: _newSignature,
                ),
              ),
            ),
          )
        else
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              child: ContentWidth.bar(
                child: ViewerActionBar(
                  onPages: () => _organise(local),
                  onEdit: () {
                    if (_searching) _closeSearch();
                    setState(() => _editing = true);
                  },
                  onShare: () => _share(local, document?.title ?? 'Document'),
                  onAskAi: () => _askAi(document),
                ),
              ),
            ),
          ),
        if (_saving) const BusyOverlay(label: 'Saving changes…'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final document = ref.watch(documentDetailProvider(_id)).value;
    final saved = _saved;
    final local = saved != null
        ? AsyncData(saved)
        : ref.watch(localPdfProvider(_id));

    return PopScope(
      // Back closes search or the editor before it leaves the screen
      canPop: !_editing && !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_editing) {
          if (!_saving) _closeEditor();
        } else {
          _closeSearch();
        }
      },
      child: Scaffold(
        backgroundColor: _canvasColor,
        appBar: _editing
            ? _editBar(local.value)
            : _searching
            ? _searchBar()
            : _viewBar(document),
        // After a save that changed the text the document is processed
        // again; keep checking so Ask AI unlocks without leaving the screen
        body: PollWhile(
          active: document?.isInProgress ?? false,
          onTick: () => ref.invalidate(documentDetailProvider(_id)),
          child: local.when(
            skipLoadingOnReload: true,
            loading: () => const LoadingView(label: 'Opening PDF…'),
            error: (error, _) => MessageView.error(
              message: errorMessage(error),
              onRetry: () => ref.invalidate(localPdfProvider(_id)),
            ),
            data: (local) => _viewer(local, document),
          ),
        ),
        bottomNavigationBar: _editing
            ? DecoratedBox(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: IgnorePointer(
                      ignoring: _saving,
                      child: ContentWidth.bar(
                        child: EditToolBar(
                          session: _session,
                          onSelect: _selectTool,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}
