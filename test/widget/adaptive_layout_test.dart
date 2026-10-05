import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_genesis/core/layout/responsive.dart';
import 'package:pdf_genesis/core/storage/app_prefs.dart';
import 'package:pdf_genesis/core/theme/app_theme.dart';
import 'package:pdf_genesis/features/auth/application/auth_controller.dart';
import 'package:pdf_genesis/features/documents/data/document.dart';
import 'package:pdf_genesis/features/documents/data/documents_repository.dart';
import 'package:pdf_genesis/features/viewer/application/edit_session.dart';
import 'package:pdf_genesis/features/viewer/presentation/edit_toolbars.dart';
import 'package:pdf_genesis/features/viewer/presentation/widgets/viewer_action_bar.dart';
import 'package:pdf_genesis/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

void main() {
  test('window sizes follow the 600 and 840 breakpoints', () {
    expect(WindowSize.fromWidth(320), WindowSize.compact);
    expect(WindowSize.fromWidth(599), WindowSize.compact);
    expect(WindowSize.fromWidth(600), WindowSize.medium);
    expect(WindowSize.fromWidth(839), WindowSize.medium);
    expect(WindowSize.fromWidth(840), WindowSize.expanded);
  });

  test('the grid adds a column each time another item fits', () {
    expect(AdaptiveGrid.columnsFor(288, 340, 12), 1);
    expect(AdaptiveGrid.columnsFor(691, 340, 12), 1);
    expect(AdaptiveGrid.columnsFor(692, 340, 12), 2);
    expect(AdaptiveGrid.columnsFor(1044, 340, 12), 3);
  });

  testWidgets('the grid gives every item in a row the same width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: AdaptiveGrid(
            minItemWidth: 300,
            children: [
              SizedBox(key: ValueKey('a'), height: 40),
              SizedBox(key: ValueKey('b'), height: 40),
              SizedBox(key: ValueKey('c'), height: 40),
            ],
          ),
        ),
      ),
    );

    final a = tester.getRect(find.byKey(const ValueKey('a')));
    final b = tester.getRect(find.byKey(const ValueKey('b')));
    final c = tester.getRect(find.byKey(const ValueKey('c')));
    expect(a.width, 394);
    expect(b.width, a.width);
    expect(b.top, a.top);
    // The third item wraps to a second row
    expect(c.top, greaterThan(a.bottom));
    expect(c.left, a.left);
  });

  group('navigation', () {
    Future<void> pumpApp(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({'onboarding_seen': true});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appPrefsProvider.overrideWithValue(AppPrefs(prefs)),
            authControllerProvider.overrideWith(
              () => FakeAuthController(googleUser),
            ),
            recentDocumentsProvider.overrideWith(
              (ref) async => [
                document(),
                document(id: 'doc-2', title: 'Lease'),
              ],
            ),
            documentsListProvider.overrideWith(
              (ref, query) async => <Document>[],
            ),
          ],
          child: const PdfGenesisApp(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pumpAndSettle();
    }

    testWidgets('a phone gets the bottom bar', (tester) async {
      await pumpApp(tester, const Size(390, 844));

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    for (final (name, size) in [
      ('a tablet', const Size(800, 1280)),
      ('a phone in landscape', const Size(844, 390)),
    ]) {
      testWidgets('$name gets the side rail, and it switches tabs', (
        tester,
      ) async {
        await pumpApp(tester, size);

        expect(find.byType(NavigationRail), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Documents'));
        await tester.pumpAndSettle();
        expect(find.text('No documents yet'), findsOneWidget);
      });
    }

    testWidgets(
      'a wide tablet shows upload and recent documents side by side',
      (tester) async {
        await pumpApp(tester, const Size(1280, 800));

        final upload = tester.getRect(find.text('Add a document'));
        final recent = tester.getRect(find.text('Recent Documents'));
        expect(recent.left, greaterThan(upload.right));

        // The two recent documents share one row
        final first = tester.getRect(find.text('Q3 Financial Report'));
        final second = tester.getRect(find.text('Lease'));
        expect(second.top, first.top);
        expect(second.left, greaterThan(first.right));
      },
    );

    testWidgets('a phone stacks them', (tester) async {
      await pumpApp(tester, const Size(390, 844));

      final upload = tester.getRect(find.text('Add a document'));
      final recent = tester.getRect(find.text('Recent Documents'));
      expect(recent.top, greaterThan(upload.bottom));
    });
  });

  group('viewer bars', () {
    Future<void> pumpBar(WidgetTester tester, Size size, Widget bar) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, app) => MediaQuery.withClampedTextScaling(
            minScaleFactor: 1.3,
            maxScaleFactor: 1.3,
            child: app!,
          ),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: ContentWidth(maxWidth: ContentWidths.toolbar, child: bar),
            ),
          ),
        ),
      );
    }

    testWidgets('the action bar fits a small phone with large text', (
      tester,
    ) async {
      await pumpBar(
        tester,
        const Size(320, 568),
        ViewerActionBar(
          onPages: () {},
          onEdit: () {},
          onShare: () {},
          onAskAi: () {},
          askAiLocked: true,
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('the tool bar fits a small phone with large text', (
      tester,
    ) async {
      final session = EditSession();
      addTearDown(session.dispose);

      await pumpBar(
        tester,
        const Size(320, 568),
        EditToolBar(session: session, onSelect: (_) {}),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('on a tablet the action bar stays compact and centred', (
      tester,
    ) async {
      await pumpBar(
        tester,
        const Size(1280, 800),
        ViewerActionBar(
          onPages: () {},
          onEdit: () {},
          onShare: () {},
          onAskAi: () {},
        ),
      );

      final bar = tester.getRect(find.byType(ViewerActionBar));
      expect(bar.width, ContentWidths.toolbar);
      expect(bar.center.dx, 640);
    });
  });
}
