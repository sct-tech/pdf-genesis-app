import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_genesis/core/network/api_exception.dart';
import 'package:pdf_genesis/features/auth/application/auth_controller.dart';
import 'package:pdf_genesis/features/auth/data/app_user.dart';
import 'package:pdf_genesis/features/chat/data/chat_repository.dart';
import 'package:pdf_genesis/features/chat/presentation/chat_screen.dart';
import 'package:pdf_genesis/features/documents/data/documents_repository.dart';

import '../support/fakes.dart';

void main() {
  FakeChatRepository withHistory() => FakeChatRepository(
    conversations: {
      'latest': [
        chatMessage('m1', 'What is the total fare?', isUser: true),
        chatMessage('m2', 'The total fare is 1,600.00.'),
      ],
      'older': [
        chatMessage('m3', 'What is the PNR number?', isUser: true),
        chatMessage('m4', 'The PNR is VE20260517.'),
      ],
    },
  );

  Future<void> pumpChat(
    WidgetTester tester,
    FakeChatRepository repository, {
    String? conversationId,
    String? initialQuestion,
    int? questionsLeft,
  }) async {
    final overrides = <Override>[
      usageProvider.overrideWith(
        (ref) async => Usage(
          documentsUsed: 1,
          documentsLimit: 3,
          pdfUploadsToday: 0,
          aiChatsToday: 0,
          summariesToday: 0,
          questionsLeft: questionsLeft,
          questionsLimit: questionsLeft == null ? null : 3,
        ),
      ),
      authControllerProvider.overrideWith(() => FakeAuthController(googleUser)),
      chatRepositoryProvider.overrideWithValue(repository),
      documentDetailProvider.overrideWith((ref, id) async => document()),
      suggestedQuestionsProvider.overrideWith(
        (ref, id) async => ['What are the main risks?'],
      ),
    ];
    await pumpScreen(
      tester,
      ChatScreen(
        documentId: 'doc-1',
        conversationId: conversationId,
        initialQuestion: initialQuestion,
      ),
      overrides: overrides,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('opening the chat shows the most recent conversation', (
    tester,
  ) async {
    await pumpChat(tester, withHistory());

    expect(find.text('What is the total fare?'), findsOneWidget);
    expect(find.text('The total fare is 1,600.00.'), findsOneWidget);
    // The other conversation is not mixed in
    expect(find.text('What is the PNR number?'), findsNothing);
  });

  testWidgets('a new question continues that conversation', (tester) async {
    final repository = withHistory();
    await pumpChat(tester, repository);

    await tester.enterText(find.byType(TextField), 'And the discount?');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(repository.created, isEmpty);
    expect(repository.sent.single.conversationId, 'latest');
    expect(find.text('What is the total fare?'), findsOneWidget);
    expect(find.text('Answer to: And the discount?'), findsOneWidget);
  });

  testWidgets('a suggested question from the document is asked after the '
      'history has loaded', (tester) async {
    final repository = withHistory();
    await pumpChat(tester, repository, initialQuestion: 'Who is travelling?');

    expect(repository.sent.single, (
      conversationId: 'latest',
      content: 'Who is travelling?',
    ));
    expect(find.text('What is the total fare?'), findsOneWidget);
    expect(find.text('Answer to: Who is travelling?'), findsOneWidget);
  });

  testWidgets('with no history the chat starts empty with suggestions', (
    tester,
  ) async {
    final repository = FakeChatRepository();
    await pumpChat(tester, repository);

    expect(find.text('Ask anything about this PDF'), findsOneWidget);
    expect(find.text('What are the main risks?'), findsOneWidget);
    // Nothing to start over from yet
    final newChat = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.add_comment_outlined),
    );
    expect(newChat.onPressed, isNull);
  });

  testWidgets('New chat clears the screen and the next question opens a new '
      'conversation', (tester) async {
    final repository = withHistory();
    await pumpChat(tester, repository);

    await tester.tap(find.byTooltip('New chat'));
    await tester.pumpAndSettle();
    expect(find.text('What is the total fare?'), findsNothing);
    expect(find.text('Ask anything about this PDF'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'A fresh question');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(repository.created, ['new-1']);
    expect(repository.sent.single.conversationId, 'new-1');
    // The earlier conversation is untouched
    expect(repository.threads['latest'], hasLength(2));
  });

  testWidgets('history lists every conversation and opens the one tapped', (
    tester,
  ) async {
    await pumpChat(tester, withHistory());

    await tester.tap(find.byTooltip('Chat history'));
    await tester.pumpAndSettle();

    expect(find.text('Chat history'), findsOneWidget);
    // Titles in the sheet; the current one is also a bubble behind it
    expect(find.text('What is the PNR number?'), findsOneWidget);
    expect(find.text('The PNR is VE20260517.'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.tap(find.text('What is the PNR number?'));
    await tester.pumpAndSettle();

    expect(find.text('Chat history'), findsNothing);
    expect(find.text('The PNR is VE20260517.'), findsOneWidget);
    expect(find.text('The total fare is 1,600.00.'), findsNothing);
  });

  testWidgets('a conversation opened from the document is shown as asked', (
    tester,
  ) async {
    await pumpChat(tester, withHistory(), conversationId: 'older');

    expect(find.text('The PNR is VE20260517.'), findsOneWidget);
    expect(find.text('The total fare is 1,600.00.'), findsNothing);
  });

  testWidgets('when the history cannot be loaded, retry is offered', (
    tester,
  ) async {
    await pumpChat(tester, FakeChatRepository(failListing: true));

    expect(find.text('Could not load'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('the chat counts down the free questions left today', (
    tester,
  ) async {
    final repository = withHistory()..questionsLeft = 2;
    await pumpChat(tester, repository, questionsLeft: 2);

    expect(find.text('2 of 3 free questions left today'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'And the discount?');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(find.text('1 of 3 free questions left today'), findsOneWidget);
  });

  testWidgets('sending is off once the free questions are used', (
    tester,
  ) async {
    final repository = withHistory()..questionsLeft = 1;
    await pumpChat(tester, repository, questionsLeft: 1);

    await tester.enterText(find.byType(TextField), 'Last one?');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(find.text('Daily limit reached'), findsOneWidget);
    expect(
      find.text(
        "You have asked today's 3 free questions. You can ask again tomorrow.",
      ),
      findsOneWidget,
    );
    // Earlier answers stay readable; only asking is switched off
    expect(find.text('Answer to: Last one?'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byTooltip('Send'), findsNothing);
  });

  testWidgets('an empty chat offers nothing to ask once the limit is reached', (
    tester,
  ) async {
    await pumpChat(tester, FakeChatRepository(), questionsLeft: 0);

    expect(find.text('Daily limit reached'), findsOneWidget);
    expect(find.text('What are the main risks?'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a refusal for the daily limit offers no retry', (tester) async {
    const refusal = ApiException(
      message: "You have used today's 3 free questions.",
      name: 'DailyLimitReached',
      status: 429,
    );
    final repository = FakeChatRepository(sendError: refusal);
    // The count the app holds is stale: another device used the questions
    await pumpChat(tester, repository, questionsLeft: 2);

    await tester.enterText(find.byType(TextField), 'What is the fare?');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    // The limit bar explains it; no error row or retry is left behind
    expect(find.text('Daily limit reached'), findsOneWidget);
    expect(find.text(refusal.message), findsNothing);
    expect(find.text('Retry'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('an ordinary failure still offers a retry', (tester) async {
    final repository = FakeChatRepository(
      sendError: const ApiException(message: 'The assistant is unavailable.'),
    );
    await pumpChat(tester, repository, questionsLeft: 2);

    await tester.enterText(find.byType(TextField), 'What is the fare?');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('2 of 3 free questions left today'), findsOneWidget);
  });

  testWidgets('no count is shown when the API reports no allowance', (
    tester,
  ) async {
    await pumpChat(tester, withHistory());

    expect(find.textContaining('left today'), findsNothing);
  });
}
