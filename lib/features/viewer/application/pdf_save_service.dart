import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../core/storage/app_prefs.dart';
import '../../documents/application/document_actions.dart';
import '../../documents/data/documents_repository.dart';
import '../../documents/data/pdf_file_store.dart';
import '../data/edit_marks.dart';
import '../data/page_assembler.dart';
import '../data/pdf_mark_writer.dart';

/// Turns edits into a new PDF, stores it, and brings the rest of the app up
/// to date.
///
/// Screens take this from the provider before their first `await`: it holds
/// the provider's own [Ref], so a save that outlives its screen still
/// refreshes the document lists.
class PdfSaveService {
  PdfSaveService(this._ref);

  final Ref _ref;

  /// Writes [marks] into the PDF at [source].
  ///
  /// [changesText] is true when the marks add readable text, in which case
  /// the assistant re-reads the document.
  Future<LocalPdf> saveMarks({
    required String documentId,
    required LocalPdf source,
    required List<EditMark> marks,
    required bool changesText,
  }) async {
    final bytes = await PdfMarkWriter.apply(
      path: source.path,
      marks: marks,
      baselineRatio: TextMark.baselineRatio,
    );
    return _store(documentId, bytes, reprocess: changesText);
  }

  /// Saves a document made of [pages], in that order. Page changes always
  /// alter the text, so the assistant re-reads the document.
  Future<LocalPdf> savePages({
    required String documentId,
    required List<PdfPage> pages,
  }) async {
    final bytes = await assemblePages(pages);
    return _store(documentId, bytes, reprocess: true);
  }

  Future<LocalPdf> _store(
    String documentId,
    Uint8List bytes, {
    required bool reprocess,
  }) async {
    final saved = await _ref
        .read(pdfFileStoreProvider)
        .saveRevision(documentId, bytes, reprocess: reprocess);
    _ref.invalidate(documentDetailProvider(documentId));
    _ref.read(documentActionsProvider).refresh();
    return saved;
  }
}

final pdfSaveServiceProvider = Provider<PdfSaveService>(PdfSaveService.new);

/// The signature last drawn on this device, offered again by the Sign tool.
class SignatureStore {
  SignatureStore(this._prefs);

  final AppPrefs _prefs;

  Signature? load() {
    final stored = _prefs.signature;
    if (stored == null) return null;
    try {
      return Signature.fromJson(stored);
    } on Object {
      // Saved by a build whose format no longer parses: draw a new one
      return null;
    }
  }

  Future<void> save(Signature signature) =>
      _prefs.setSignature(signature.toJson());
}

final signatureStoreProvider = Provider<SignatureStore>(
  (ref) => SignatureStore(ref.watch(appPrefsProvider)),
);
