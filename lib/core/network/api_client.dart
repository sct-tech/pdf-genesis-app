import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';

/// A list response together with its pagination block.
class ApiPage {
  const ApiPage({required this.items, required this.total});

  final List<dynamic> items;
  final int total;
}

/// Thin wrapper over Dio for the PDF Genesis API.
///
/// Adds the bearer token, refreshes it once when the API reports it expired,
/// and unwraps the `{ success, data, meta }` envelope.
class ApiClient {
  ApiClient({required this._tokens, Dio? dio, Dio? plainDio})
    : _dio = dio ?? Dio(_options),
      _plain = plainDio ?? Dio(_options) {
    _dio.interceptors.add(
      QueuedInterceptorsWrapper(onRequest: _onRequest, onError: _onError),
    );
  }

  static final _options = BaseOptions(
    baseUrl: '${AppConfig.apiBaseUrl}/api/v1',
    connectTimeout: const Duration(seconds: 15),
    // Summaries of large PDFs can take a while
    receiveTimeout: const Duration(seconds: 120),
    contentType: Headers.jsonContentType,
  );

  final TokenStorage _tokens;
  final Dio _dio;

  /// No interceptors: used for the refresh call and the one retry, so neither
  /// can re-enter the queued interceptor.
  final Dio _plain;

  final _sessionExpired = StreamController<void>.broadcast();

  /// Fires when the refresh token is rejected and the user must sign in again.
  Stream<void> get onSessionExpired => _sessionExpired.stream;

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _tokens.accessToken;
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  Future<void> _onError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final data = error.response?.data;
    final expired =
        error.response?.statusCode == 401 &&
        data is Map &&
        data['name'] == 'TokenExpired';
    if (!expired) return handler.next(error);

    final refreshToken = await _tokens.refreshToken;
    if (refreshToken == null) {
      await _endSession();
      return handler.next(error);
    }

    final String accessToken;
    try {
      final refreshed = await _plain.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final payload = refreshed.data!['data'] as Map<String, dynamic>;
      accessToken = payload['accessToken'] as String;
      await _tokens.save(
        accessToken: accessToken,
        refreshToken: payload['refreshToken'] as String,
      );
    } on DioException catch (refreshError) {
      // Only a rejected refresh token ends the session; being offline does not.
      if (refreshError.response?.statusCode == 401) {
        await _endSession();
      }
      return handler.next(refreshError);
    }

    // Outside the block above: the session is good now, so whatever the
    // retried request answers is that request's own result.
    try {
      final request = error.requestOptions
        ..headers['Authorization'] = 'Bearer $accessToken';
      handler.resolve(await _plain.fetch<dynamic>(request));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  Future<void> _endSession() async {
    await _tokens.clear();
    _sessionExpired.add(null);
  }

  ApiException _toException(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) {
      return ApiException(
        message: data['message'] as String,
        name: (data['name'] as String?) ?? 'Error',
        status: error.response?.statusCode,
      );
    }
    if (error.response == null) return const ApiException.network();
    return ApiException(
      message: 'Something went wrong. Please try again.',
      status: error.response?.statusCode,
    );
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async {
    try {
      final response = await _dio.request<Map<String, dynamic>>(
        path,
        data: body,
        queryParameters: query,
        options: Options(method: method),
      );
      return response.data ?? const {};
    } on DioException catch (error) {
      throw _toException(error);
    }
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async =>
      (await _send('GET', path, query: query))['data'];

  Future<ApiPage> getPage(String path, {Map<String, dynamic>? query}) async {
    final envelope = await _send('GET', path, query: query);
    final meta = envelope['meta'] as Map<String, dynamic>?;
    final items = (envelope['data'] as List<dynamic>?) ?? const [];
    return ApiPage(
      items: items,
      total: (meta?['total'] as int?) ?? items.length,
    );
  }

  Future<dynamic> post(String path, {Object? body}) async =>
      (await _send('POST', path, body: body))['data'];

  Future<dynamic> delete(String path) async =>
      (await _send('DELETE', path))['data'];

  void dispose() {
    _sessionExpired.close();
    _dio.close();
    _plain.close();
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(tokens: ref.watch(tokenStorageProvider));
  ref.onDispose(client.dispose);
  return client;
});
