import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/documents_repository.dart';
import '../data/pdf_file_store.dart';

/// Changes to the user's documents that have to keep several things in step:
/// the API, the copies cached for the viewer, and every list on screen.
///
/// Screens take this from the provider before their first `await`. It holds
/// the provider's own [Ref], so it stays usable when the widget that started
/// an action has gone by the time the action finishes.
class DocumentActions {
  DocumentActions(this._ref);

  final Ref _ref;

  /// Reloads every list that shows documents or the stored-document count.
  void refresh() {
    _ref
      ..invalidate(recentDocumentsProvider)
      ..invalidate(documentsListProvider)
      ..invalidate(usageProvider);
  }

  Future<void> delete(String documentId) async {
    await _ref.read(documentsRepositoryProvider).delete(documentId);
    // Best effort: the document is gone either way
    await _ref.read(pdfFileStoreProvider).evict(documentId).catchError((_) {});
    _ref.invalidate(documentDetailProvider(documentId));
    refresh();
  }

  Future<void> deleteAll() async {
    await _ref.read(documentsRepositoryProvider).deleteAll();
    await _ref.read(pdfFileStoreProvider).evictAll().catchError((_) {});
    refresh();
  }
}

final documentActionsProvider = Provider<DocumentActions>(DocumentActions.new);
