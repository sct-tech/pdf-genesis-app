import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_genesis/features/viewer/application/edit_session.dart';
import 'package:pdf_genesis/features/viewer/application/touch_tracker.dart';
import 'package:pdf_genesis/features/viewer/data/edit_marks.dart';
import 'package:pdf_genesis/features/viewer/presentation/page_edit_layer.dart';

void main() {
  late EditSession session;
  late List<({int page, Offset position, TextMark? existing})> textRequests;
  late List<({int page, Offset position})> signatureRequests;

  setUp(() {
    session = EditSession();
    textRequests = [];
    signatureRequests = [];
  });
  tearDown(() => session.dispose());

  /// Two 200x200 pages stacked, as two pages share one viewer.
  Future<void> pumpPages(WidgetTester tester) {
    final touches = TouchTracker();
    Widget page(int number) => SizedBox(
      key: ValueKey('page-$number'),
      width: 200,
      height: 200,
      child: PageEditLayer(
        page: number,
        session: session,
        touches: touches,
        onTextRequested: (page, position, _, existing) => textRequests.add((
          page: page,
          position: position,
          existing: existing,
        )),
        onSignatureRequested: (page, position, _) =>
            signatureRequests.add((page: page, position: position)),
      ),
    );
    return tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [page(1), page(2)],
          ),
        ),
      ),
    );
  }

  Offset onPage(WidgetTester tester, int page, Offset fraction) {
    final rect = tester.getRect(find.byKey(ValueKey('page-$page')));
    return rect.topLeft +
        Offset(fraction.dx * rect.width, fraction.dy * rect.height);
  }

  testWidgets('with no tool the layer lets touches through', (tester) async {
    await pumpPages(tester);

    await tester.dragFrom(
      onPage(tester, 1, const Offset(0.2, 0.2)),
      const Offset(60, 0),
    );

    expect(session.marks, isEmpty);
  });

  testWidgets('the pen draws a stroke on the page that was touched', (
    tester,
  ) async {
    await pumpPages(tester);
    session.tool = EditTool.pen;
    await tester.pump();

    await tester.dragFrom(
      onPage(tester, 2, const Offset(0.25, 0.5)),
      const Offset(100, 0),
    );

    final stroke = session.marks.single as StrokeMark;
    expect(stroke.page, 2);
    expect(stroke.points.first.dx, closeTo(0.25, 0.01));
    expect(stroke.points.last.dx, closeTo(0.75, 0.01));
    expect(session.canUndo, isTrue);
  });

  testWidgets('a second finger on the same page cancels the stroke', (
    tester,
  ) async {
    await pumpPages(tester);
    session.tool = EditTool.pen;
    await tester.pump();

    final first = await tester.startGesture(
      onPage(tester, 1, const Offset(0.2, 0.2)),
      pointer: 1,
    );
    await first.moveBy(const Offset(40, 0));
    final second = await tester.startGesture(
      onPage(tester, 1, const Offset(0.8, 0.8)),
      pointer: 2,
    );
    await second.up();
    await first.up();

    expect(session.marks, isEmpty);
    expect(session.draft, isNull);
  });

  testWidgets('after a pinch across two pages the remaining finger does not '
      'go on erasing', (tester) async {
    await pumpPages(tester);
    session.tool = EditTool.pen;
    await tester.pump();
    await tester.dragFrom(
      onPage(tester, 1, const Offset(0.1, 0.8)),
      const Offset(160, 0),
    );
    expect(session.marks, hasLength(1));

    session.tool = EditTool.eraser;
    await tester.pump();
    final first = await tester.startGesture(
      onPage(tester, 1, const Offset(0.5, 0.2)),
      pointer: 1,
    );
    // The second finger lands on the other page
    final second = await tester.startGesture(
      onPage(tester, 2, const Offset(0.5, 0.5)),
      pointer: 2,
    );
    await second.up();
    // The first finger then wanders over the stroke
    await first.moveTo(onPage(tester, 1, const Offset(0.5, 0.8)));
    await first.up();

    expect(session.marks, hasLength(1));
  });

  testWidgets('the eraser removes the mark under the finger', (tester) async {
    await pumpPages(tester);
    session.tool = EditTool.pen;
    await tester.pump();
    await tester.dragFrom(
      onPage(tester, 1, const Offset(0.1, 0.5)),
      const Offset(160, 0),
    );

    session.tool = EditTool.eraser;
    await tester.pump();
    await tester.tapAt(onPage(tester, 1, const Offset(0.5, 0.5)));

    expect(session.marks, isEmpty);
  });

  testWidgets('tapping with the text tool asks for a new note there', (
    tester,
  ) async {
    await pumpPages(tester);
    session.tool = EditTool.text;
    await tester.pump();

    await tester.tapAt(onPage(tester, 1, const Offset(0.5, 0.25)));

    final request = textRequests.single;
    expect(request.page, 1);
    expect(request.position.dx, closeTo(0.5, 0.01));
    expect(request.position.dy, closeTo(0.25, 0.01));
    expect(request.existing, isNull);
  });

  testWidgets('dragging a note moves it as a single undo step', (tester) async {
    await pumpPages(tester);
    session
      ..tool = EditTool.text
      ..addText(1, const Offset(0.1, 0.1), 'Note', 1);
    await tester.pump();
    final note = session.marks.single as TextMark;

    await tester.timedDragFrom(
      onPage(tester, 1, note.bounds.center),
      const Offset(60, 40),
      const Duration(milliseconds: 200),
    );

    final moved = session.marks.single as TextMark;
    expect(moved.position.dx, closeTo(0.4, 0.02));
    expect(moved.position.dy, closeTo(0.3, 0.02));
    // A drag is not a tap: no dialog was asked for
    expect(textRequests, isEmpty);

    session.undo();
    expect((session.marks.single as TextMark).position, note.position);
  });

  testWidgets('tapping an existing note asks to edit that note', (
    tester,
  ) async {
    await pumpPages(tester);
    session
      ..tool = EditTool.text
      ..addText(1, const Offset(0.1, 0.1), 'Note', 1);
    await tester.pump();
    final note = session.marks.single as TextMark;

    await tester.tapAt(onPage(tester, 1, note.bounds.center));

    expect(textRequests.single.existing?.id, note.id);
  });

  testWidgets('tapping with the sign tool asks to place the signature', (
    tester,
  ) async {
    await pumpPages(tester);
    session.tool = EditTool.sign;
    await tester.pump();

    await tester.tapAt(onPage(tester, 2, const Offset(0.5, 0.5)));

    expect(signatureRequests.single.page, 2);
  });
}
