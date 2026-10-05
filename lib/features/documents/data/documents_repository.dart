import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/presigned_transfer.dart';
import '../../auth/application/auth_controller.dart';
import 'document.dart';

class DocumentsRepository {
  DocumentsRepository(this._api, this._transfer);

  final ApiClient _api;
  final PresignedTransfer _transfer;

  Future<List<Document>> list({
    String search = '',
    DocumentSort sort = DocumentSort.newest,
    int limit = 50,
  }) async {
    final page = await _api.getPage(
      '/documents',
      query: {
        'limit': limit,
        'sort': sort.name,
        if (search.isNotEmpty) 'search': search,
      },
    );
    return [
      for (final item in page.items)
        Document.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<Document> detail(String id) async {
    final data = await _api.get('/documents/$id');
    return Document.fromJson(data as Map<String, dynamic>);
  }

  /// Uploads straight to storage with a presigned URL, then asks the API to
  /// start processing. Returns the new document's id.
  Future<String> upload({
    required Stream<List<int>> Function() openRead,
    required String filename,
    required int fileSize,
    required void Function(double progress) onProgress,
    CancelToken? cancelToken,
  }) async {
    final ticket = await _api.post(
      '/documents/upload-url',
      body: {'filename': filename, 'fileSize': fileSize},
    ) as Map<String, dynamic>;
    final documentId = ticket['documentId'] as String;

    try {
      await _transfer.upload(
        url: ticket['uploadUrl'] as String,
        headers: (ticket['uploadHeaders'] as Map<String, dynamic>? ?? {}).map(
          (key, value) => MapEntry(key, value.toString()),
        ),
        data: openRead(),
        length: fileSize,
        failureMessage: 'Upload failed. Please try again.',
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    } catch (_) {
      // Free the slot the abandoned upload would otherwise hold for an hour
      await delete(documentId).catchError((_) {});
      rethrow;
    }

    await _api.post('/documents/$documentId/complete');
    return documentId;
  }

  Future<void> retry(String id) => _api.post('/documents/$id/retry');

  Future<void> delete(String id) => _api.delete('/documents/$id');

  Future<void> deleteAll() => _api.delete('/documents');

  /// Generated on first request, served from cache afterwards.
  Future<DocumentSummary> summary(String id) async {
    final data = await _api.post('/documents/$id/summary');
    return DocumentSummary.fromJson(data as Map<String, dynamic>);
  }

  Future<List<String>> suggestedQuestions(String id) async {
    final data = await _api.get(
      '/documents/$id/suggested-questions',
    ) as Map<String, dynamic>;
    return [
      for (final question in (data['questions'] as List<dynamic>? ?? const []))
        question as String,
    ];
  }
}

final documentsRepositoryProvider = Provider<DocumentsRepository>(
  (ref) => DocumentsRepository(
    ref.watch(apiClientProvider),
    ref.watch(presignedTransferProvider),
  ),
);

final documentsListProvider = FutureProvider.autoDispose
    .family<List<Document>, DocumentsQuery>((ref, query) {
      ref.watch(currentUserProvider.select((user) => user?.id));
      return ref
          .watch(documentsRepositoryProvider)
          .list(search: query.search, sort: query.sort);
    });

/// Latest uploads for the Home screen.
final recentDocumentsProvider = FutureProvider.autoDispose<List<Document>>((
  ref,
) {
  ref.watch(currentUserProvider.select((user) => user?.id));
  return ref.watch(documentsRepositoryProvider).list(limit: 5);
});

final documentDetailProvider = FutureProvider.autoDispose
    .family<Document, String>(
      (ref, id) => ref.watch(documentsRepositoryProvider).detail(id),
    );

final documentSummaryProvider = FutureProvider.autoDispose
    .family<DocumentSummary, String>(
      (ref, id) => ref.watch(documentsRepositoryProvider).summary(id),
    );

final suggestedQuestionsProvider = FutureProvider.autoDispose
    .family<List<String>, String>(
      (ref, id) =>
          ref.watch(documentsRepositoryProvider).suggestedQuestions(id),
    );
