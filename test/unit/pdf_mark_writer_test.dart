import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_genesis/features/viewer/data/edit_marks.dart';
import 'package:pdf_genesis/features/viewer/data/pdf_mark_writer.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/sample_pdf.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pdf_genesis_test');
    // No path_provider plugin under `flutter test`
    Pdfrx.cacheDirectoryPath = temp.path;
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Future<String> pageText(String path, int pageNumber) async {
    final document = await PdfDocument.openFile(path);
    try {
      final text = await document.pages[pageNumber - 1].loadText();
      return text?.fullText ?? '';
    } finally {
      await document.dispose();
    }
  }

  test('writes strokes, text and signatures into the right pages', () async {
    final source = File('${temp.path}/source.pdf')
      ..writeAsBytesSync(buildSamplePdf(['First page', 'Second page']));

    final bytes = await PdfMarkWriter.apply(
      path: source.path,
      baselineRatio: 1,
      marks: [
        StrokeMark(
          id: 1,
          page: 1,
          points: [Offset(0.1, 0.1), Offset(0.5, 0.2), Offset(0.6, 0.4)],
          color: Color(0xFF2563EB),
          width: 0.004,
        ),
        StrokeMark(
          id: 2,
          page: 1,
          points: [Offset(0.1, 0.5), Offset(0.8, 0.5)],
          color: Color(0x66FACC15),
          width: 0.03,
          highlighter: true,
        ),
        TextMark(
          id: 3,
          page: 2,
          position: Offset(0.2, 0.3),
          text: 'Check this figure\nSecond line',
          color: Color(0xFFDC2626),
          size: 0.03,
        ),
        const SignatureMark(
          id: 4,
          page: 2,
          rect: Rect.fromLTWH(0.5, 0.8, 0.3, 0.1),
          color: Color(0xFF0F172A),
          signature: Signature(
            aspectRatio: 3,
            strokes: [
              [Offset(0, 1), Offset(0.5, 0), Offset(1, 1)],
            ],
          ),
        ),
      ],
    );

    final edited = File('${temp.path}/edited.pdf')..writeAsBytesSync(bytes);
    expect(await pageText(edited.path, 1), contains('First page'));
    expect(await pageText(edited.path, 1), isNot(contains('Check this')));
    final second = await pageText(edited.path, 2);
    expect(second, contains('Second page'));
    expect(second, contains('Check this figure'));
    expect(second, contains('Second line'));
  });

  test('a mark that cannot be written fails the whole save', () async {
    final source = File('${temp.path}/source.pdf')
      ..writeAsBytesSync(buildSamplePdf(['Only page']));

    await expectLater(
      PdfMarkWriter.apply(
        path: source.path,
        baselineRatio: 1,
        marks: [
          StrokeMark(
            id: 1,
            // The document has one page
            page: 7,
            points: [const Offset(0.1, 0.1), const Offset(0.5, 0.5)],
            color: const Color(0xFF2563EB),
            width: 0.004,
          ),
        ],
      ),
      throwsA(isA<PdfWriteException>()),
    );
  });

  /// Renders page 1 at 72 dpi and reports whether anything is drawn in
  /// [area], given in normalised page coordinates.
  Future<bool> hasInk(String path, Rect area) async {
    final document = await PdfDocument.openFile(path);
    try {
      final page = document.pages.first;
      final image = (await page.render())!;
      try {
        final left = (area.left * image.width).floor();
        final right = (area.right * image.width).ceil();
        final top = (area.top * image.height).floor();
        final bottom = (area.bottom * image.height).ceil();
        for (var y = top; y < bottom; y++) {
          for (var x = left; x < right; x++) {
            final i = (y * image.width + x) * 4;
            // Any channel off pure white counts
            if (image.pixels[i] < 250 ||
                image.pixels[i + 1] < 250 ||
                image.pixels[i + 2] < 250) {
              return true;
            }
          }
        }
        return false;
      } finally {
        image.dispose();
      }
    } finally {
      await document.dispose();
    }
  }

  for (final rotation in [0, 90]) {
    testWidgets(
      'a note in another script is placed as an image (page rotated $rotation)',
      (tester) async {
        await tester.runAsync(() async {
          final source = File('${temp.path}/source.pdf')
            ..writeAsBytesSync(buildSamplePdf(['Hello'], rotation: rotation));
          final note = TextMark(
            id: 1,
            page: 1,
            position: const Offset(0.3, 0.6),
            text: 'नमस्ते दुनिया',
            color: const Color(0xFFDC2626),
            size: 0.05,
            pageAspectRatio: rotation == 0 ? 612 / 792 : 792 / 612,
          );

          final bytes = await PdfMarkWriter.apply(
            path: source.path,
            baselineRatio: 1,
            marks: [note],
          );

          final edited = File('${temp.path}/edited.pdf')
            ..writeAsBytesSync(bytes);
          expect(await hasInk(source.path, note.bounds), isFalse);
          expect(await hasInk(edited.path, note.bounds), isTrue);
          // Nothing spills outside the note's box
          expect(
            await hasInk(edited.path, const Rect.fromLTRB(0.3, 0.8, 0.9, 0.95)),
            isFalse,
          );
          // An image adds no readable text
          expect(await pageText(edited.path, 1), isNot(contains('नमस्ते')));
        });
      },
    );
  }
}
