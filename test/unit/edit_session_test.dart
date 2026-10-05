import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_genesis/features/viewer/application/edit_session.dart';
import 'package:pdf_genesis/features/viewer/data/edit_marks.dart';

void main() {
  const signature = Signature(
    aspectRatio: 2,
    strokes: [
      [Offset(0, 1), Offset(1, 0)],
    ],
  );

  EditSession drawing(EditTool tool) => EditSession()..tool = tool;

  void drawLine(EditSession session, Offset from, Offset to, {int page = 1}) {
    session
      ..startStroke(page, from)
      ..extendStroke(to)
      ..endStroke();
  }

  group('EditSession', () {
    test('a finished stroke becomes a mark and can be undone and redone', () {
      final session = drawing(EditTool.pen);
      drawLine(session, const Offset(0.1, 0.1), const Offset(0.4, 0.1));

      expect(session.marks, hasLength(1));
      expect(session.draft, isNull);
      expect(session.hasChanges, isTrue);

      session.undo();
      expect(session.marks, isEmpty);
      expect(session.canRedo, isTrue);

      session.redo();
      expect(session.marks, hasLength(1));
    });

    test('a new edit after undo drops the redo history', () {
      final session = drawing(EditTool.pen);
      drawLine(session, const Offset(0.1, 0.1), const Offset(0.4, 0.1));
      session.undo();
      drawLine(session, const Offset(0.1, 0.5), const Offset(0.4, 0.5));

      expect(session.canRedo, isFalse);
      expect(session.marks, hasLength(1));
    });

    test('a cancelled stroke leaves nothing behind', () {
      final session = drawing(EditTool.pen)
        ..startStroke(1, const Offset(0.2, 0.2))
        ..cancelStroke();

      expect(session.marks, isEmpty);
      expect(session.canUndo, isFalse);
    });

    test('highlighter strokes are see-through and use the highlight width', () {
      final session = drawing(EditTool.highlight);
      drawLine(session, const Offset(0.1, 0.1), const Offset(0.4, 0.1));

      final mark = session.marks.single as StrokeMark;
      expect(mark.highlighter, isTrue);
      expect(mark.color.a, lessThan(1));
      expect(mark.width, session.size);
    });

    test('hit testing finds a stroke between its points, on its page only', () {
      final session = drawing(EditTool.pen);
      drawLine(session, const Offset(0.1, 0.5), const Offset(0.9, 0.5));

      expect(session.hitTest(1, const Offset(0.5, 0.505)), isNotNull);
      expect(session.hitTest(1, const Offset(0.5, 0.8)), isNull);
      expect(session.hitTest(2, const Offset(0.5, 0.5)), isNull);
    });

    test('a note saved as an image does not change the readable text', () {
      final session = drawing(EditTool.text)
        ..addText(1, const Offset(0.2, 0.2), 'नमस्ते', 0.75);

      expect(session.hasChanges, isTrue);
      expect(session.changesText, isFalse);
    });

    test('only typed notes change the readable text', () {
      final session = drawing(EditTool.pen);
      drawLine(session, const Offset(0.1, 0.1), const Offset(0.4, 0.1));
      session.addSignature(1, const Offset(0.5, 0.5), signature, 0.75);
      expect(session.changesText, isFalse);

      session.addText(1, const Offset(0.2, 0.2), 'Note', 0.75);
      expect(session.changesText, isTrue);
    });

    test('a signature keeps its shape on the page and when resized', () {
      final session = drawing(EditTool.sign)
        ..addSignature(1, const Offset(0.5, 0.5), signature, 0.75);

      var mark = session.marks.single as SignatureMark;
      expect(mark.rect.center, const Offset(0.5, 0.5));
      // Normalised height is scaled by the page's aspect ratio
      expect(mark.rect.height, closeTo(mark.rect.width / 2 * 0.75, 1e-9));

      session.setSize(0.5);
      mark = session.marks.single as SignatureMark;
      expect(mark.rect.width, closeTo(0.5, 1e-9));
      expect(mark.rect.height, closeTo(0.5 / 2 * 0.75, 1e-9));
      expect(mark.rect.center.dx, closeTo(0.5, 1e-9));
    });

    test(
      'restyling the selected note is undoable; a slider drag is one step',
      () {
        final session = drawing(EditTool.text)
          ..addText(1, const Offset(0.2, 0.2), 'Note', 0.75);
        final original = (session.marks.single as TextMark).size;

        session
          ..setSize(0.04)
          ..setSize(0.05, record: false)
          ..setSize(0.06, record: false);
        expect((session.marks.single as TextMark).size, 0.06);

        session.undo();
        expect((session.marks.single as TextMark).size, original);
      },
    );

    test('removing a mark clears the selection', () {
      final session = drawing(EditTool.text)
        ..addText(1, const Offset(0.2, 0.2), 'Note', 0.75);
      expect(session.selected, isNotNull);

      session.remove(session.marks.single);
      expect(session.selected, isNull);
      expect(session.marks, isEmpty);
    });
  });

  group('Signature', () {
    test('is cropped to what was drawn', () {
      final cropped = Signature.fromPad([
        [const Offset(50, 100), const Offset(250, 200)],
      ]);

      expect(cropped.aspectRatio, 2);
      expect(cropped.strokes.single, const [Offset(0, 0), Offset(1, 1)]);
    });

    test('survives being stored as JSON', () {
      final restored = Signature.fromJson(signature.toJson());

      expect(restored.aspectRatio, signature.aspectRatio);
      expect(restored.strokes, signature.strokes);
    });
  });

  test('typographic punctuation is replaced with plain characters', () {
    expect(
      plainPunctuation('\u201CDon\u2019t\u201D \u2013 wait\u2026'),
      '"Don\'t" - wait...',
    );
  });

  group('TextMark', () {
    TextMark note(String text) => TextMark(
      id: 1,
      page: 1,
      position: Offset.zero,
      text: text,
      color: const Color(0xFF000000),
      size: 0.03,
    );

    test('Latin-1 notes are saved as real text', () {
      expect(note('Total: £250 - café').isSelectableInPdf, isTrue);
    });

    test('typographic punctuation does not force a note into an image', () {
      final mark = note('It\u2019s \u2014 fine\u2026');

      expect(mark.isSelectableInPdf, isTrue);
      expect(mark.pdfText, "It's - fine...");
    });

    test('other scripts are saved as an image of the text', () {
      expect(note('नमस्ते').isSelectableInPdf, isFalse);
      expect(note('નમસ્તે').isSelectableInPdf, isFalse);
      expect(note('مرحبا').isSelectableInPdf, isFalse);
      expect(note('你好 👍').isSelectableInPdf, isFalse);
    });
  });
}
