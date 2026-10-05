import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_genesis/core/network/api_exception.dart';
import 'package:pdf_genesis/core/storage/app_prefs.dart';
import 'package:pdf_genesis/features/auth/application/auth_controller.dart';
import 'package:pdf_genesis/features/auth/data/app_user.dart';
import 'package:pdf_genesis/features/auth/presentation/login_screen.dart';
import 'package:pdf_genesis/features/chat/data/chat_repository.dart';
import 'package:pdf_genesis/features/chat/presentation/chat_screen.dart';
import 'package:pdf_genesis/features/documents/data/document.dart';
import 'package:pdf_genesis/features/documents/data/documents_repository.dart';
import 'package:pdf_genesis/features/documents/presentation/document_detail_screen.dart';
import 'package:pdf_genesis/features/documents/presentation/documents_screen.dart';
import 'package:pdf_genesis/features/documents/presentation/processing_screen.dart';
import 'package:pdf_genesis/features/documents/presentation/summary_screen.dart';
import 'package:pdf_genesis/features/documents/presentation/upload_screen.dart';
import 'package:pdf_genesis/features/home/presentation/home_screen.dart';
import 'package:pdf_genesis/features/profile/presentation/profile_screen.dart';
import 'package:pdf_genesis/features/profile/presentation/settings_screen.dart';
import 'package:pdf_genesis/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

Override _auth(AppUser? user) =>
    authControllerProvider.overrideWith(() => FakeAuthController(user));

const _usage = Usage(
  documentsUsed: 2,
  documentsLimit: 3,
  pdfUploadsToday: 1,
  aiChatsToday: 12,
  summariesToday: 1,
);

void main() {
  testWidgets('first launch goes splash, three onboarding slides, then login', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appPrefsProvider.overrideWithValue(AppPrefs(prefs)),
          _auth(null),
        ],
        child: const PdfGenesisApp(),
      ),
    );
    expect(find.text('Ask Anything From PDF'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();
    expect(find.text('Understand Any PDF Instantly'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Ask Anything'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Save Hours of Reading'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);

    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.textContaining('Apple'), findsNothing);
    expect(prefs.getBool('onboarding_seen'), isTrue);
  });

  testWidgets('Login offers Google sign-in as the only way in', (tester) async {
    await pumpScreen(tester, const LoginScreen(), overrides: [_auth(null)]);

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.bySubtype<ButtonStyleButton>(), findsOneWidget);
    expect(find.text('Continue as Guest'), findsNothing);
    expect(find.textContaining('Guest'), findsNothing);
  });

  testWidgets('a returning signed-in user lands on Home with three tabs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'onboarding_seen': true});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appPrefsProvider.overrideWithValue(AppPrefs(prefs)),
          _auth(googleUser),
          recentDocumentsProvider.overrideWith((ref) async => <Document>[]),
        ],
        child: const PdfGenesisApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();

    expect(find.textContaining(', Milan'), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(3));
    expect(find.text('AI Chat'), findsNothing);
    expect(find.text('No documents yet'), findsOneWidget);
  });

  testWidgets('Home lists recent documents with status and quick actions', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const HomeScreen(),
      overrides: [
        _auth(googleUser),
        recentDocumentsProvider.overrideWith(
          (ref) async => [
            document(),
            document(
              id: 'doc-2',
              title:
                  'A very long document title that must not overflow the row',
              status: ProcessingStatus.processing,
              pageCount: null,
            ),
            document(
              id: 'doc-3',
              title: 'Scan',
              status: ProcessingStatus.failed,
            ),
          ],
        ),
      ],
    );
    await tester.pump();

    expect(find.text('Upload PDF'), findsOneWidget);
    expect(find.text('Recent Documents'), findsOneWidget);
    expect(find.text('Q3 Financial Report'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Processing'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Chat'), findsNWidgets(3));
    expect(find.text('Summary'), findsNWidgets(3));
    expect(find.text('More'), findsNWidgets(3));
    await unmount(tester);
  });

  testWidgets('Documents shows the empty state', (tester) async {
    await pumpScreen(
      tester,
      const DocumentsScreen(),
      overrides: [
        _auth(googleUser),
        documentsListProvider.overrideWith((ref, query) async => <Document>[]),
      ],
    );
    await tester.pump();
    expect(find.text('No documents yet'), findsOneWidget);
  });

  testWidgets('Documents shows the error state with retry', (tester) async {
    await pumpScreen(
      tester,
      const DocumentsScreen(),
      overrides: [
        _auth(googleUser),
        documentsListProvider.overrideWith(
          (ref, query) async => throw const ApiException.network(),
        ),
      ],
    );
    await tester.pump();
    expect(find.text('Could not load'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('Documents lists items and toggles the sort order', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const DocumentsScreen(),
      overrides: [
        _auth(googleUser),
        documentsListProvider.overrideWith(
          (ref, query) async => [
            document(),
            document(id: 'doc-2', title: 'Lease'),
          ],
        ),
      ],
    );
    await tester.pump();
    expect(find.text('Sort: Newest first'), findsOneWidget);
    expect(find.text('Lease'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.text('Sort: Newest first'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Sort: Oldest first'), findsOneWidget);
  });

  testWidgets('Upload shows the file rules', (tester) async {
    await pumpScreen(
      tester,
      const UploadScreen(),
      overrides: [_auth(googleUser)],
    );
    expect(find.text('PDF files only'), findsOneWidget);
    expect(find.text('Maximum 50 MB'), findsOneWidget);
    expect(find.text('Maximum 500 pages'), findsOneWidget);
  });

  testWidgets('Processing shows the five steps and lets the user leave', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const ProcessingScreen(documentId: 'doc-1'),
      overrides: [
        _auth(googleUser),
        documentDetailProvider.overrideWith(
          (ref, id) async => document(
            status: ProcessingStatus.processing,
            stage: 'UNDERSTANDING_CONTENT',
          ),
        ),
      ],
    );
    await tester.pump();

    for (final step in [
      'Uploading document',
      'Reading pages',
      'Understanding content',
      'Preparing AI assistant',
      'Ready',
    ]) {
      expect(find.text(step), findsOneWidget);
    }
    // Two steps done, the third running
    expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
    expect(find.text('Continue in background'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Processing shows the failure reason with retry and delete', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const ProcessingScreen(documentId: 'doc-1'),
      overrides: [
        _auth(googleUser),
        documentDetailProvider.overrideWith(
          (ref, id) async => document(
            status: ProcessingStatus.failed,
            error: 'This PDF has no readable text.',
          ),
        ),
      ],
    );
    await tester.pump();

    expect(find.text('This PDF has no readable text.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Delete PDF'), findsOneWidget);
  });

  testWidgets('Document detail shows metadata, actions and suggestions', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const DocumentDetailScreen(documentId: 'doc-1'),
      overrides: [
        _auth(googleUser),
        documentDetailProvider.overrideWith(
          (ref, id) async => document(
            suggestedQuestions: ['What is this document about?'],
          ),
        ),
        usageProvider.overrideWith((ref) async => _usage),
      ],
    );
    await tester.pump();

    expect(find.text('Pages'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('12.0 MB'), findsOneWidget);
    final ask = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Ask Anything'),
        matching: find.bySubtype<FilledButton>(),
      ),
    );
    expect(ask.onPressed, isNotNull);
    expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
    expect(find.text('Generate Summary'), findsOneWidget);
    expect(find.text('View & Edit PDF'), findsOneWidget);
    expect(find.text('What is this document about?'), findsOneWidget);
  });

  OutlinedButton summaryButton(WidgetTester tester, String label) =>
      tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text(label),
          matching: find.bySubtype<OutlinedButton>(),
        ),
      );

  Usage usageWith({int summariesLeft = 1}) => Usage(
    documentsUsed: 1,
    documentsLimit: 3,
    pdfUploadsToday: 0,
    aiChatsToday: 0,
    summariesToday: 0,
    questionsLeft: 3,
    questionsLimit: 3,
    summariesLeft: summariesLeft,
    aiMaxPages: 100,
  );

  Future<void> pumpDetail(
    WidgetTester tester,
    Document shown,
    Usage usage,
  ) async {
    var questionRequests = 0;
    await pumpScreen(
      tester,
      const DocumentDetailScreen(documentId: 'doc-1'),
      overrides: [
        _auth(googleUser),
        documentDetailProvider.overrideWith((ref, id) async => shown),
        usageProvider.overrideWith((ref) async => usage),
        suggestedQuestionsProvider.overrideWith((ref, id) async {
          questionRequests += 1;
          return const <String>[];
        }),
      ],
    );
    await tester.pumpAndSettle();
    // Opening the screen must not prepare the document for AI
    expect(questionRequests, 0);
  }

  testWidgets('Generate Summary is off once today\'s summary is used', (
    tester,
  ) async {
    await pumpDetail(tester, document(), usageWith(summariesLeft: 0));

    expect(summaryButton(tester, 'Generate Summary').onPressed, isNull);
    expect(
      find.text(
        "You have used today's summary. A new one is available tomorrow.",
      ),
      findsOneWidget,
    );
    expect(find.text('Suggested questions'), findsNothing);
  });

  testWidgets('a summary that exists stays open after the limit', (
    tester,
  ) async {
    await pumpDetail(
      tester,
      document(hasSummary: true),
      usageWith(summariesLeft: 0),
    );

    expect(summaryButton(tester, 'View Summary').onPressed, isNotNull);
    expect(find.textContaining("today's summary"), findsNothing);
  });

  testWidgets('a PDF over the page limit has AI switched off', (tester) async {
    await pumpDetail(tester, document(pageCount: 240), usageWith());

    final ask = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Ask Anything'),
        matching: find.bySubtype<FilledButton>(),
      ),
    );
    expect(ask.onPressed, isNull);
    expect(summaryButton(tester, 'Generate Summary').onPressed, isNull);
    expect(
      find.text('Ask AI and summaries work with PDFs of up to 100 pages.'),
      findsOneWidget,
    );
    // Reading and editing are unaffected
    expect(summaryButton(tester, 'View & Edit PDF').onPressed, isNotNull);
  });

  testWidgets('a refused summary says why instead of loading', (tester) async {
    await pumpScreen(
      tester,
      const SummaryScreen(documentId: 'doc-1'),
      overrides: [
        _auth(googleUser),
        documentDetailProvider.overrideWith((ref, id) async => document()),
        documentSummaryProvider.overrideWith(
          (ref, id) async => throw const ApiException(
            message:
                "You have used today's summary. A new one is available tomorrow.",
            name: 'DailyLimitReached',
            status: 429,
          ),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Generating summary…'), findsNothing);
    expect(find.text('Daily limit reached'), findsOneWidget);
    expect(
      find.text(
        "You have used today's summary. A new one is available tomorrow.",
      ),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsNothing);
    expect(find.text('Go back'), findsOneWidget);
  });

  testWidgets('Summary shows both sections with copy and share', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const SummaryScreen(documentId: 'doc-1'),
      overrides: [
        _auth(googleUser),
        documentDetailProvider.overrideWith((ref, id) async => document()),
        documentSummaryProvider.overrideWith(
          (ref, id) async => const DocumentSummary(
            summary: 'Revenue grew 24% year over year.',
            keyPoints: ['ARR reached 42.8M', 'Churn fell to 1.1%'],
          ),
        ),
      ],
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Document Summary'), findsOneWidget);
    expect(find.text('Key Points'), findsOneWidget);
    expect(find.text('Churn fell to 1.1%'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.textContaining('Export'), findsNothing);
  });

  testWidgets('an empty chat offers suggested prompts and the input', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const ChatScreen(documentId: 'doc-1'),
      overrides: [
        _auth(googleUser),
        chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
        documentDetailProvider.overrideWith((ref, id) async => document()),
        suggestedQuestionsProvider.overrideWith(
          (ref, id) async => ['What are the main risks mentioned?'],
        ),
      ],
    );
    // The chat first looks for an earlier conversation to continue
    await tester.pumpAndSettle();

    expect(find.text('Ask anything from this PDF…'), findsOneWidget);
    expect(find.text('What are the main risks mentioned?'), findsOneWidget);
    expect(find.byTooltip('Voice - Coming Soon'), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);
  });

  testWidgets('Profile shows the account and stored PDFs against the limit', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const ProfileScreen(),
      overrides: [
        _auth(googleUser),
        usageProvider.overrideWith((ref) async => _usage),
      ],
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Milan Patel'), findsOneWidget);
    expect(find.text('milan@example.com'), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.textContaining('plan'), findsNothing);
    expect(find.textContaining('Upgrade'), findsNothing);
  });

  testWidgets('Settings lists account, data and about actions', (tester) async {
    await pumpScreen(
      tester,
      const SettingsScreen(),
      overrides: [_auth(googleUser)],
    );
    await tester.pump();

    expect(find.text('milan@example.com'), findsOneWidget);
    expect(find.text('Delete all documents'), findsOneWidget);
    expect(find.text('Clear chat history'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Terms of Service'), findsOneWidget);

    await tester.tap(find.text('Delete all documents'));
    await tester.pumpAndSettle();
    expect(find.text('Delete all documents?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });
}
