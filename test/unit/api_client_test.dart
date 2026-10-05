import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_genesis/core/network/api_client.dart';
import 'package:pdf_genesis/core/network/api_exception.dart';

import '../support/fakes.dart';

const _expired = (
  status: 401,
  body: {
    'success': false,
    'status': 401,
    'name': 'TokenExpired',
    'message': 'Token is invalid or has expired',
  },
);

ApiClient _client(FakeTokenStorage tokens, FakeHandler handler) {
  final options = BaseOptions(baseUrl: 'http://api.test/api/v1');
  final adapter = FakeAdapter(handler);
  return ApiClient(
    tokens: tokens,
    dio: Dio(options)..httpClientAdapter = adapter,
    plainDio: Dio(options)..httpClientAdapter = adapter,
  );
}

void main() {
  test('unwraps the data envelope and sends the bearer token', () async {
    final tokens = FakeTokenStorage(access: 'access-1', refresh: 'refresh-1');
    String? authorization;
    final client = _client(tokens, (request) {
      authorization = request.headers['Authorization'] as String?;
      return (
        status: 200,
        body: {
          'success': true,
          'data': {'id': 'u1'},
        },
      );
    });

    expect(await client.get('/users/me'), {'id': 'u1'});
    expect(authorization, 'Bearer access-1');
  });

  test('returns list items with the total from meta', () async {
    final client = _client(
      FakeTokenStorage(access: 'a', refresh: 'r'),
      (_) => (
        status: 200,
        body: {
          'success': true,
          'data': [
            {'id': 'd1'},
            {'id': 'd2'},
          ],
          'meta': {'page': 1, 'limit': 2, 'total': 7, 'totalPages': 4},
        },
      ),
    );

    final page = await client.getPage('/documents');
    expect(page.items, hasLength(2));
    expect(page.total, 7);
  });

  test('refreshes an expired token once and retries the request', () async {
    final tokens = FakeTokenStorage(access: 'old', refresh: 'refresh-1');
    final seen = <String>[];
    final client = _client(tokens, (request) {
      final auth = request.headers['Authorization'];
      seen.add('${request.method} ${request.path} $auth');
      if (request.path == '/auth/refresh') {
        expect(request.data, {'refreshToken': 'refresh-1'});
        return (
          status: 200,
          body: {
            'success': true,
            'data': {'accessToken': 'new', 'refreshToken': 'refresh-2'},
          },
        );
      }
      if (auth == 'Bearer old') return _expired;
      return (status: 200, body: {'success': true, 'data': 'ok'});
    });

    expect(await client.get('/documents'), 'ok');
    expect(tokens.access, 'new');
    expect(tokens.refresh, 'refresh-2');
    expect(seen, [
      'GET /documents Bearer old',
      'POST /auth/refresh null',
      'GET /documents Bearer new',
    ]);
  });

  test('ends the session when the refresh token is rejected', () async {
    final tokens = FakeTokenStorage(access: 'old', refresh: 'refresh-1');
    final client = _client(tokens, (request) {
      if (request.path == '/auth/refresh') {
        return (
          status: 401,
          body: {
            'success': false,
            'status': 401,
            'name': 'SessionExpired',
            'message': 'Session has expired. Please sign in again.',
          },
        );
      }
      return _expired;
    });
    var expired = 0;
    client.onSessionExpired.listen((_) => expired++);

    await expectLater(
      client.get('/documents'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.name, 'name', 'SessionExpired')
            .having((e) => e.isUnauthorized, 'isUnauthorized', isTrue),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(tokens.access, isNull);
    expect(tokens.refresh, isNull);
    expect(expired, 1);
  });

  test('a rejected retry after a good refresh keeps the session', () async {
    final tokens = FakeTokenStorage(access: 'old', refresh: 'refresh-1');
    final client = _client(tokens, (request) {
      if (request.path == '/auth/refresh') {
        return (
          status: 200,
          body: {
            'success': true,
            'data': {'accessToken': 'new', 'refreshToken': 'refresh-2'},
          },
        );
      }
      if (request.headers['Authorization'] == 'Bearer old') return _expired;
      // The retried request itself is refused, e.g. the account lost access
      return (
        status: 401,
        body: {
          'success': false,
          'status': 401,
          'name': 'Unauthorized',
          'message': 'Not allowed',
        },
      );
    });
    var expired = 0;
    client.onSessionExpired.listen((_) => expired++);

    await expectLater(
      client.get('/documents'),
      throwsA(
        isA<ApiException>().having((e) => e.name, 'name', 'Unauthorized'),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(tokens.access, 'new');
    expect(tokens.refresh, 'refresh-2');
    expect(expired, 0);
  });

  test('maps an API error to its name and message', () async {
    final client = _client(
      FakeTokenStorage(access: 'a', refresh: 'r'),
      (_) => (
        status: 403,
        body: {
          'success': false,
          'status': 403,
          'name': 'DocumentLimitReached',
          'message': 'Free plan allows 3 PDFs. Delete one or upgrade to Pro.',
        },
      ),
    );

    await expectLater(
      client.post('/documents/upload-url', body: {'filename': 'a.pdf'}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.name, 'name', 'DocumentLimitReached')
            .having((e) => e.status, 'status', 403)
            .having((e) => e.message, 'message', contains('3 PDFs')),
      ),
    );
  });

  test('reports a network error when the server is unreachable', () async {
    final client = _client(
      FakeTokenStorage(access: 'a', refresh: 'r'),
      (request) => throw DioException.connectionError(
        requestOptions: request,
        reason: 'offline',
      ),
    );

    await expectLater(
      client.get('/documents'),
      throwsA(
        isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', true),
      ),
    );
  });
}
