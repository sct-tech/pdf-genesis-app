import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_genesis/core/storage/app_prefs.dart';
import 'package:pdf_genesis/features/auth/application/auth_controller.dart';
import 'package:pdf_genesis/features/auth/data/app_user.dart';
import 'package:pdf_genesis/features/auth/presentation/login_screen.dart';
import 'package:pdf_genesis/features/auth/presentation/onboarding_screen.dart';
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
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

/// Every screen has to lay out without overflowing on each of these.
const _surfaces = <String, ({Size size, double textScale})>{
  'small phone': (size: Size(320, 568), textScale: 1),
  'small phone, large text': (size: Size(320, 568), textScale: 1.3),
  'phone': (size: Size(390, 844), textScale: 1),
  'phone landscape': (size: Size(844, 390), textScale: 1),
  'small phone landscape': (size: Size(568, 320), textScale: 1),
  'tablet': (size: Size(800, 1280), textScale: 1),
  'tablet landscape': (size: Size(1280, 800), textScale: 1),
};

const _usage = Usage(
  documentsUsed: 2,
  documentsLimit: 3,
  pdfUploadsToday: 1,
  aiChatsToday: 12,
  summariesToday: 1,
);

const _longTitle = 'A very long document title that must not overflow the row';

List<Document> _documents() => [
  document(),
  document(
    id: 'doc-2',
    title: _longTitle,
    status: ProcessingStatus.processing,
    pageCount: null,
  ),
  document(id: 'doc-3', title: 'Scan', status: ProcessingStatus.failed),
];

void main() {
  late AppPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = AppPrefs(await SharedPreferences.getInstance());
  });

  List<Override> overrides(AppUser user) => [
    authControllerProvider.overrideWith(() => FakeAuthController(user)),
    appPrefsProvider.overrideWithValue(prefs),
    usageProvider.overrideWith((ref) async => _usage),
    recentDocumentsProvider.overrideWith((ref) async => _documents()),
    documentsListProvider.overrideWith((ref, query) async => _documents()),
    documentDetailProvider.overrideWith(
      (ref, id) async => document(
        title: _longTitle,
        status: id == 'processing'
            ? ProcessingStatus.processing
            : ProcessingStatus.ready,
        stage: id == 'processing' ? 'UNDERSTANDING_CONTENT' : null,
      ),
    ),
    suggestedQuestionsProvider.overrideWith(
      (ref, id) async => [
        'What is this document about?',
        'What are the main risks mentioned in the third section of the report?',
      ],
    ),
    documentSummaryProvider.overrideWith(
      (ref, id) async => const DocumentSummary(
        summary: 'Revenue grew 24% year over year.',
        keyPoints: ['ARR reached 42.8M', 'Churn fell to 1.1%'],
      ),
    ),
  ];

  final screens = <String, (AppUser, Widget)>{
    'Onboarding': (googleUser, const OnboardingScreen()),
    'Login': (googleUser, const LoginScreen()),
    'Home': (googleUser, const HomeScreen()),
    'Home as a guest': (guestUser, const HomeScreen()),
    'Documents': (googleUser, const DocumentsScreen()),
    'Upload': (googleUser, const UploadScreen()),
    'Processing': (
      googleUser,
      const ProcessingScreen(documentId: 'processing'),
    ),
    'Document detail': (
      googleUser,
      const DocumentDetailScreen(documentId: 'doc-1'),
    ),
    'Document detail as a guest': (
      guestUser,
      const DocumentDetailScreen(documentId: 'doc-1'),
    ),
    'Summary': (googleUser, const SummaryScreen(documentId: 'doc-1')),
    'Chat': (googleUser, const ChatScreen(documentId: 'doc-1')),
    'Chat as a guest': (guestUser, const ChatScreen(documentId: 'doc-1')),
    'Profile': (googleUser, const ProfileScreen()),
    'Profile as a guest': (guestUser, const ProfileScreen()),
    'Settings': (googleUser, const SettingsScreen()),
    'Pro': (googleUser, const ProScreen()),
  };

  for (final MapEntry(key: name, value: (user, screen)) in screens.entries) {
    for (final MapEntry(key: surface, value: spec) in _surfaces.entries) {
      testWidgets('$name fits a $surface', (tester) async {
        await pumpScreen(
          tester,
          screen,
          overrides: overrides(user),
          size: spec.size,
          textScale: spec.textScale,
        );
        await tester.pump();
        await tester.pump();

        expect(tester.takeException(), isNull);
        await unmount(tester);
      });
    }
  }
}
