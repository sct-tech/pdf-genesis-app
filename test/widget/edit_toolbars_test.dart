import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_genesis/core/theme/app_theme.dart';
import 'package:pdf_genesis/features/viewer/application/edit_session.dart';
import 'package:pdf_genesis/features/viewer/presentation/edit_toolbars.dart';

void main() {
  late EditSession session;

  setUp(() => session = EditSession());
  tearDown(() => session.dispose());

  Future<void> pumpStrip(WidgetTester tester, double width) {
    tester.view.physicalSize = Size(width, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: EditOptionsStrip(session: session, onNewSignature: () {}),
        ),
      ),
    );
  }

  testWidgets('the options fit a narrow phone with every action showing', (
    tester,
  ) async {
    // The widest row: colours, New and Delete together
    session
      ..tool = EditTool.text
      ..addText(1, const Offset(0.1, 0.1), 'Note', 1)
      ..tool = EditTool.sign;
    session.select(session.marks.single);

    await pumpStrip(tester, 320);

    expect(tester.takeException(), isNull);
    expect(find.text('New'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsOneWidget);
  });

  testWidgets('nothing is shown while no tool is active', (tester) async {
    await pumpStrip(tester, 320);

    expect(find.byType(Slider), findsNothing);
  });
}
