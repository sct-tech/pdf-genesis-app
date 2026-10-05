import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_exception.dart';

/// Moves file bytes to and from storage with presigned URLs.
///
/// Uses its own Dio instance: a presigned URL carries its own signature and
/// must not receive our auth header.
class PresignedTransfer {
  PresignedTransfer([Dio? dio])
    : _dio =
          dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 15)));

  final Dio _dio;

  /// PUTs [data] to [url]. [headers] must be exactly the ones the URL was
  /// signed with. A cancelled upload rethrows the [DioException].
  Future<void> upload({
    required String url,
    required Map<String, String> headers,
    required Stream<List<int>> data,
    required int length,
    required String failureMessage,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      await _dio.put<void>(
        url,
        data: data,
        options: Options(
          headers: {...headers, Headers.contentLengthHeader: length},
          sendTimeout: const Duration(minutes: 10),
        ),
        onSendProgress: onProgress == null
            ? null
            : (sent, total) => onProgress(total <= 0 ? 0 : sent / total),
        cancelToken: cancelToken,
      );
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      throw _toException(error, failureMessage, 'UploadFailed');
    }
  }

  /// Downloads [url] into the file at [savePath].
  Future<void> download({
    required String url,
    required String savePath,
    required String failureMessage,
  }) async {
    try {
      await _dio.download(
        url,
        savePath,
        options: Options(receiveTimeout: const Duration(minutes: 10)),
      );
    } on DioException catch (error) {
      throw _toException(error, failureMessage, 'DownloadFailed');
    }
  }

  ApiException _toException(DioException error, String message, String name) {
    final offline = switch (error.type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => true,
      _ => false,
    };
    return offline
        ? const ApiException.network()
        : ApiException(message: message, name: name);
  }
}

final presignedTransferProvider = Provider<PresignedTransfer>(
  (ref) => PresignedTransfer(),
);
