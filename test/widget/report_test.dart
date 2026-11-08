import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_genesis/core/network/api_client.dart';
import 'package:pdf_genesis/features/auth/application/auth_controller.dart';
import 'package:pdf_genesis/features/chat/data/chat_models.dart';
import 'package:pdf_genesis/features/chat/data/chat_repository.dart';
import 'package:pdf_genesis/features/chat/presentation/chat_screen.dart';
import 'package:pdf_genesis/features/documents/data/documents_repository.dart';
import 'package:pdf_genesis/features/reports/data/report_repository.dart';

import '../support/fakes.dart';

/// A report repository whose requests go to [adapter] instead of the network.
ReportRepository _reports(FakeAdapter adapter) {
  final options = BaseOptions(baseUrl: 'http://api.test/api/v1');
  return ReportRepository(
    ApiClient(
      tokens: FakeTokenStorage(access: 'a', refresh: 'r'),
      dio: Dio(options)..httpClientAdapter = adapter,
      plainDio: Dio(options)..httpClientAdapter = adapter,
    ),
  );
}

Future<void> _openChat(WidgetTester tester, FakeAdapter adapter) async {
  await pumpScreen(
    tester,
    const ChatScreen(documentId: 'doc-1'),
    overrides: [
      authControllerProvider.overrideWith(
        () => FakeAuthController(googleUser),
      ),
      chatRepositoryProvider.overrideWithValue(
        FakeChatRepository(
          conversations: {
            'c1': const [
              ChatMessage(id: 'm1', isUser: true, content: 'Question?'),
              ChatMessage(id: 'm2', isUser: false, content: 'An AI answer'),
            ],
          },
        ),
      ),
      documentDetailProvider.overrideWith((ref, id) async => document()),
      suggestedQuestionsProvider.overrideWith((ref, id) async => const []),
      reportRepositoryProvider.overrideWithValue(_reports(adapter)),
    ],
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an AI answer can be reported with a reason and details', (
    tester,
  ) async {
    final adapter = FakeAdapter(
      (_) => (
        status: 201,
        body: {
          'success': true,
          'data': {'id': 'r1', 'alreadyReported': false},
        },
      ),
    );
    await _openChat(tester, adapter);

    expect(find.text('An AI answer'), findsOneWidget);
    await tester.tap(find.byTooltip('Report answer'));
    await tester.pumpAndSettle();

    expect(find.text('Report answer'), findsWidgets);
    final send = find.widgetWithText(FilledButton, 'Send report');
    expect(tester.widget<FilledButton>(send).onPressed, isNull);

    await tester.tap(find.text('Wrong or misleading'));
    await tester.enterText(find.byType(TextField).last, '  Made up a number ');
    await tester.pump();
    await tester.tap(send);
    await tester.pumpAndSettle();

    expect(adapter.requests, hasLength(1));
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/reports');
    expect(jsonDecode(jsonEncode(request.data)), {
      'target': 'CHAT_MESSAGE',
      'messageId': 'm2',
      'reason': 'INACCURATE',
      'details': 'Made up a number',
    });
    expect(find.text('Send report'), findsNothing);
    expect(find.text('Thanks. We will review this report.'), findsOneWidget);
  });

  testWidgets('a failed report stays open with the error', (tester) async {
    final adapter = FakeAdapter(
      (_) => (
        status: 404,
        body: {
          'success': false,
          'status': 404,
          'name': 'NotFound',
          'message': 'Answer not found',
        },
      ),
    );
    await _openChat(tester, adapter);

    await tester.tap(find.byTooltip('Report answer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Offensive or hateful'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send report'));
    await tester.pumpAndSettle();

    expect(find.text('Answer not found'), findsOneWidget);
    expect(find.text('Send report'), findsOneWidget);
  });

  test('a summary report names the document, not a message', () {
    expect(const SummaryReport('doc-1').body, {
      'target': 'SUMMARY',
      'documentId': 'doc-1',
    });
  });
}
