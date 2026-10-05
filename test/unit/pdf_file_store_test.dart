import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_genesis/core/network/api_client.dart';
import 'package:pdf_genesis/core/network/api_exception.dart';
import 'package:pdf_genesis/core/network/presigned_transfer.dart';
import 'package:pdf_genesis/features/documents/data/pdf_file_store.dart';

import '../support/fakes.dart';

/// Fails every request the way Dio does when there is no connection.
class _OfflineAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'offline',
    );
  }

  @override
  void close({bool force = false}) {}
}

({int status, Object body}) _ok(Object data) =>
    (status: 200, body: {'success': true, 'data': data});

void main() {
  late Directory cache;

  setUp(() => cache = Directory.systemTemp.createTempSync('pdf_store_test'));
  tearDown(() => cache.deleteSync(recursive: true));

  /// A store whose API and storage are answered by the given handlers.
  ({PdfFileStore store, FakeAdapter api, FakeAdapter storage}) build({
    required FakeHandler api,
    FakeHandler? storage,
    HttpClientAdapter? apiAdapter,
  }) {
    final apiFake = FakeAdapter(api);
    final storageFake = FakeAdapter(
      storage ?? (_) => (status: 200, body: 'pdf-bytes'),
    );
    final options = BaseOptions(baseUrl: 'http://api.test/api/v1');
    final client = ApiClient(
      tokens: FakeTokenStorage(access: 'a', refresh: 'r'),
      dio: Dio(options)..httpClientAdapter = apiAdapter ?? apiFake,
      plainDio: Dio(options)..httpClientAdapter = apiAdapter ?? apiFake,
    );
    return (
      store: PdfFileStore(
        client,
        PresignedTransfer(Dio()..httpClientAdapter = storageFake),
        cacheDirectory: () async => cache,
      ),
      api: apiFake,
      storage: storageFake,
    );
  }

  FakeHandler fileTicket(String version) =>
      (_) => _ok({'url': 'http://storage.test/file', 'version': version});

  List<String> filesFor(String documentId) {
    final folder = Directory('${cache.path}/pdfs/$documentId');
    if (!folder.existsSync()) return [];
    return [for (final entry in folder.listSync()) entry.uri.pathSegments.last]
      ..sort();
  }

  group('ensureLocal', () {
    test('downloads the PDF once and serves it from the cache after', () async {
      final fixture = build(api: fileTicket('v1'));

      final first = await fixture.store.ensureLocal('doc-1');
      final second = await fixture.store.ensureLocal('doc-1');

      expect(first.version, 'v1');
      expect(File(first.path).existsSync(), isTrue);
      expect(second.path, first.path);
      expect(fixture.storage.requests, hasLength(1));
      // No half-downloaded file is left under the final name or beside it
      expect(filesFor('doc-1'), ['v1.pdf']);
    });

    test('a new version replaces the cached copy', () async {
      await build(api: fileTicket('v1')).store.ensureLocal('doc-1');

      final updated = await build(api: fileTicket('v2')).store
          .ensureLocal('doc-1');

      expect(updated.version, 'v2');
      expect(filesFor('doc-1'), ['v2.pdf']);
    });

    test('offline, a PDF opened before is served from the cache', () async {
      await build(api: fileTicket('v1')).store.ensureLocal('doc-1');

      final offline = build(api: (_) => _ok({}), apiAdapter: _OfflineAdapter());
      final local = await offline.store.ensureLocal('doc-1');

      expect(local.version, 'v1');
      expect(File(local.path).existsSync(), isTrue);
    });

    test('offline with nothing cached reports the network error', () async {
      final offline = build(api: (_) => _ok({}), apiAdapter: _OfflineAdapter());

      await expectLater(
        offline.store.ensureLocal('doc-1'),
        throwsA(
          isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', isTrue),
        ),
      );
    });

    test('a failed download leaves no file that could be opened', () async {
      final fixture = build(
        api: fileTicket('v1'),
        storage: (_) => (status: 404, body: 'gone'),
      );

      await expectLater(
        fixture.store.ensureLocal('doc-1'),
        throwsA(
          isA<ApiException>().having((e) => e.name, 'name', 'DownloadFailed'),
        ),
      );
      expect(filesFor('doc-1').where((name) => name.endsWith('.pdf')), isEmpty);
    });

    test('a version that is not a plain file name is rejected', () async {
      final fixture = build(api: fileTicket('../../outside'));

      await expectLater(
        fixture.store.ensureLocal('doc-1'),
        throwsA(isA<ApiException>()),
      );
      expect(fixture.storage.requests, isEmpty);
    });
  });

  group('saveRevision', () {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);

    FakeHandler revisionApi(List<String> calls) => (request) {
      calls.add('${request.method} ${request.path}');
      if (request.path.endsWith('/revision')) {
        expect(request.data, {'fileSize': 4});
        return _ok({
          'uploadUrl': 'http://storage.test/upload',
          'uploadHeaders': {'Content-Type': 'application/pdf'},
        });
      }
      expect(request.data, {'reprocess': true});
      return _ok({'version': 'v2'});
    };

    test('uploads, completes and keeps the new file as the copy', () async {
      await build(api: fileTicket('v1')).store.ensureLocal('doc-1');
      final calls = <String>[];
      final fixture = build(api: revisionApi(calls));

      final saved = await fixture.store.saveRevision(
        'doc-1',
        bytes,
        reprocess: true,
      );

      expect(calls, [
        'POST /documents/doc-1/revision',
        'POST /documents/doc-1/revision/complete',
      ]);
      final upload = fixture.storage.requests.single;
      expect(upload.method, 'PUT');
      expect(upload.headers['Content-Type'], 'application/pdf');
      // The storage request carries no session token
      expect(upload.headers.containsKey('Authorization'), isFalse);
      expect(saved.version, 'v2');
      expect(File(saved.path).readAsBytesSync(), bytes);
      expect(filesFor('doc-1'), ['v2.pdf']);
    });

    test('a failed upload is not completed and keeps the old copy', () async {
      await build(api: fileTicket('v1')).store.ensureLocal('doc-1');
      final calls = <String>[];
      final fixture = build(
        api: revisionApi(calls),
        storage: (_) => (status: 500, body: 'error'),
      );

      await expectLater(
        fixture.store.saveRevision('doc-1', bytes, reprocess: true),
        throwsA(
          isA<ApiException>().having((e) => e.name, 'name', 'UploadFailed'),
        ),
      );
      expect(calls, ['POST /documents/doc-1/revision']);
      expect(filesFor('doc-1'), ['v1.pdf']);
    });
  });

  group('eviction', () {
    test('evict removes one document and leaves the others', () async {
      final store = build(api: fileTicket('v1')).store;
      await store.ensureLocal('doc-1');
      await store.ensureLocal('doc-2');

      await store.evict('doc-1');

      expect(filesFor('doc-1'), isEmpty);
      expect(filesFor('doc-2'), ['v1.pdf']);
    });

    test('evictAll removes every copy and tolerates an empty cache', () async {
      final store = build(api: fileTicket('v1')).store;
      await store.evictAll();
      await store.ensureLocal('doc-1');

      await store.evictAll();

      expect(Directory('${cache.path}/pdfs').existsSync(), isFalse);
    });
  });
}
