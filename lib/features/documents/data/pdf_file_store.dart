import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/presigned_transfer.dart';

/// The copy of a document's PDF kept on the device for viewing and editing.
class LocalPdf {
  const LocalPdf({required this.path, required this.version});

  final String path;

  /// Identifies the stored file. A saved edit produces a new version.
  final String version;
}

/// Downloads document PDFs into the app cache and uploads edited copies.
class PdfFileStore {
  PdfFileStore(
    this._api,
    this._transfer, {
    Future<Directory> Function()? cacheDirectory,
  }) : _cacheDirectory = cacheDirectory ?? getApplicationCacheDirectory;

  // Versions come from the API and become file names
  static final _safeVersion = RegExp(r'^[A-Za-z0-9_-]+$');

  final ApiClient _api;
  final PresignedTransfer _transfer;
  final Future<Directory> Function() _cacheDirectory;

  Future<Directory> _root() async =>
      Directory('${(await _cacheDirectory()).path}/pdfs');

  Future<Directory> _folder(String documentId) async =>
      Directory('${(await _root()).path}/$documentId');

  File _file(Directory folder, String version) {
    if (!_safeVersion.hasMatch(version)) {
      throw const ApiException(
        message: 'This PDF could not be opened. Please try again.',
        name: 'InvalidFileVersion',
      );
    }
    return File('${folder.path}/$version.pdf');
  }

  /// Leaves only [keep] in the document's folder.
  Future<void> _prune(Directory folder, File keep) async {
    // Compared by name: the platform may spell the same path with different
    // separators
    final keepName = keep.uri.pathSegments.last;
    await for (final entry in folder.list()) {
      if (entry is File && entry.uri.pathSegments.last != keepName) {
        await entry.delete().catchError((_) => entry);
      }
    }
  }

  /// The copy already on the device, if there is one.
  Future<LocalPdf?> _cached(String documentId) async {
    final folder = await _folder(documentId);
    if (!folder.existsSync()) return null;
    await for (final entry in folder.list()) {
      if (entry is File && entry.path.endsWith('.pdf')) {
        final name = entry.uri.pathSegments.last;
        return LocalPdf(
          path: entry.path,
          version: name.substring(0, name.length - '.pdf'.length),
        );
      }
    }
    return null;
  }

  /// Returns the local copy, downloading it when it is missing or outdated.
  ///
  /// Without a connection the copy already on the device is returned, so a
  /// PDF that was opened before can still be read offline.
  Future<LocalPdf> ensureLocal(String documentId) async {
    final Map<String, dynamic> ticket;
    try {
      ticket =
          await _api.get('/documents/$documentId/file') as Map<String, dynamic>;
    } on ApiException catch (error) {
      final cached = error.isNetwork ? await _cached(documentId) : null;
      if (cached == null) rethrow;
      return cached;
    }

    final version = ticket['version'] as String;
    final folder = await (await _folder(documentId)).create(recursive: true);
    final file = _file(folder, version);
    if (!file.existsSync()) {
      // Downloaded under another name so a partial file is never opened
      final partial = '${file.path}.part';
      await _transfer.download(
        url: ticket['url'] as String,
        savePath: partial,
        failureMessage: 'Could not download this PDF. Please try again.',
      );
      await File(partial).rename(file.path);
    }
    await _prune(folder, file);
    return LocalPdf(path: file.path, version: version);
  }

  /// Replaces the stored PDF with [bytes] and returns the new local copy.
  ///
  /// [reprocess] must be true when the readable text changed, so the
  /// assistant is rebuilt from the new content.
  Future<LocalPdf> saveRevision(
    String documentId,
    Uint8List bytes, {
    required bool reprocess,
  }) async {
    final ticket = await _api.post(
      '/documents/$documentId/revision',
      body: {'fileSize': bytes.length},
    ) as Map<String, dynamic>;
    await _transfer.upload(
      url: ticket['uploadUrl'] as String,
      headers: (ticket['uploadHeaders'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(key, value.toString()),
      ),
      data: Stream.value(bytes),
      length: bytes.length,
      failureMessage: 'Could not save your changes. Please try again.',
    );
    final saved = await _api.post(
      '/documents/$documentId/revision/complete',
      body: {'reprocess': reprocess},
    ) as Map<String, dynamic>;

    // The server has the new file from here on. A failure to keep a local
    // copy must not look like a failed save, or the user would save again
    // and write the same edits twice.
    try {
      final folder = await (await _folder(documentId)).create(recursive: true);
      final file = _file(folder, saved['version'] as String);
      await file.writeAsBytes(bytes, flush: true);
      await _prune(folder, file);
      return LocalPdf(path: file.path, version: saved['version'] as String);
    } on FileSystemException {
      return ensureLocal(documentId);
    }
  }

  /// Removes the local copy, e.g. after the document is deleted.
  Future<void> evict(String documentId) async {
    final folder = await _folder(documentId);
    if (folder.existsSync()) await folder.delete(recursive: true);
  }

  /// Removes every local copy, e.g. when the user signs out.
  Future<void> evictAll() async {
    final root = await _root();
    if (root.existsSync()) await root.delete(recursive: true);
  }
}

final pdfFileStoreProvider = Provider<PdfFileStore>(
  (ref) => PdfFileStore(
    ref.watch(apiClientProvider),
    ref.watch(presignedTransferProvider),
  ),
);

final localPdfProvider = FutureProvider.autoDispose.family<LocalPdf, String>(
  (ref, documentId) => ref.watch(pdfFileStoreProvider).ensureLocal(documentId),
);
