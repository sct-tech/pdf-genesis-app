import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_genesis/core/network/api_exception.dart';
import 'package:pdf_genesis/core/storage/app_prefs.dart';
import 'package:pdf_genesis/features/auth/application/auth_controller.dart';
import 'package:pdf_genesis/features/auth/data/app_user.dart';
import 'package:pdf_genesis/features/chat/presentation/chat_screen.dart';
import 'package:pdf_genesis/features/documents/data/document.dart';
import 'package:pdf_genesis/features/documents/data/documents_repository.dart';
import 'package:pdf_genesis/features/documents/presentation/document_detail_screen.dart';
import 'package:pdf_genesis/features/documents/presentation/documents_screen.dart';
import 'package:pdf_genesis/features/documents/presentation/processing_screen.dart';
import 'package:pdf_genesis/features/documents/presentation/summary_screen.dart';
import 'package:pdf_genesis/features/documents/presentation/upload_screen.dart';
import 'package:pdf_genesis/features/home/presentation/home_screen.dart';
import 'package:pdf_genesis/features/profile/presentation/pro_screen.dart';
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
    expect(find.text('Continue as Guest'), findsOneWidget);
    expect(find.textContaining('Apple'), findsNothing);
    expect(prefs.getBool('onboarding_seen'), isTrue);
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
        documentDetailProvider.overrideWith((ref, id) async => document()),
        suggestedQuestionsProvider.overrideWith(
          (ref, id) async => ['What is this document about?'],
        ),
      ],
    );
    await tester.pump();

    expect(find.text('Pages'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('12.0 MB'), findsOneWidget);
    expect(find.text('Ask Anything'), findsOneWidget);
    expect(find.text('Generate Summary'), findsOneWidget);
    expect(find.text('What is this document about?'), findsOneWidget);
  });

  testWidgets('for a guest, Ask Anything is disabled with a log-in hint', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const DocumentDetailScreen(documentId: 'doc-1'),
      overrides: [
        _auth(guestUser),
        documentDetailProvider.overrideWith((ref, id) async => document()),
        suggestedQuestionsProvider.overrideWith(
          (ref, id) async => ['What is this document about?'],
        ),
      ],
    );
    await tester.pump();

    final ask = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Ask Anything'),
        matching: find.bySubtype<FilledButton>(),
      ),
    );
    expect(ask.onPressed, isNull);
    expect(find.textContaining('PDF Genesis Ask AI feature'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    // The rest of the document stays available
    expect(find.text('Generate Summary'), findsOneWidget);
    expect(find.text('View & Edit PDF'), findsOneWidget);

    // A suggested question explains the lock instead of opening the chat
    await tester.tap(find.text('What is this document about?'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to use Ask AI'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets(
    'for a guest, the chat screen asks to sign in and sends nothing',
    (tester) async {
      await pumpScreen(
        tester,
        const ChatScreen(documentId: 'doc-1', initialQuestion: 'Any risks?'),
        overrides: [
          _auth(guestUser),
          documentDetailProvider.overrideWith((ref, id) async => document()),
        ],
      );
      await tester.pump();

      expect(find.text('Sign in to use Ask AI'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Ask anything from this PDF…'), findsNothing);
      expect(find.text('Any risks?'), findsNothing);
    },
  );

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
        documentDetailProvider.overrideWith((ref, id) async => document()),
        suggestedQuestionsProvider.overrideWith(
          (ref, id) async => ['What are the main risks mentioned?'],
        ),
      ],
    );
    await tester.pump();

    expect(find.text('Ask anything from this PDF…'), findsOneWidget);
    expect(find.text('What are the main risks mentioned?'), findsOneWidget);
    expect(find.byTooltip('Voice - Coming Soon'), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);
  });

  testWidgets('Profile shows plan, stored PDFs against the limit and upgrade', (
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
    expect(find.text('Free plan'), findsOneWidget);
    expect(find.text('Upgrade to Pro'), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('a guest is offered Google sign-in to keep documents', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const ProfileScreen(),
      overrides: [
        _auth(guestUser),
        usageProvider.overrideWith((ref) async => _usage),
      ],
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Guest'), findsOneWidget);
    expect(find.text('Keep your documents'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
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

  testWidgets('Pro compares the 3 and 10 PDF limits', (tester) async {
    await pumpScreen(tester, const ProScreen(), overrides: [_auth(googleUser)]);
    await tester.pump();

    expect(find.text('Store up to 10 PDFs'), findsOneWidget);
    expect(find.text('Store up to 3 PDFs'), findsOneWidget);
    expect(find.text('CURRENT'), findsOneWidget);
    expect(find.text('Coming soon'), findsOneWidget);
  });
}
