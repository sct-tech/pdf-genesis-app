import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_genesis/features/viewer/data/page_assembler.dart';
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

  Future<List<String>> pageTexts(String path) async {
    final document = await PdfDocument.openFile(path);
    try {
      return [
        for (final page in document.pages)
          ((await page.loadText())?.fullText ?? '').trim(),
      ];
    } finally {
      await document.dispose();
    }
  }

  Future<String> rearrange(
    String name,
    List<PdfPage> Function(List<PdfPage> pages) arrange,
  ) async {
    final source = File('${temp.path}/$name-source.pdf')
      ..writeAsBytesSync(buildSamplePdf(['One', 'Two', 'Three']));
    final document = await PdfDocument.openFile(source.path);
    try {
      final bytes = await assemblePages(arrange(document.pages));
      final output = File('${temp.path}/$name.pdf')..writeAsBytesSync(bytes);
      return output.path;
    } finally {
      await document.dispose();
    }
  }

  test('reordered pages are saved in the new order', () async {
    final path = await rearrange(
      'reorder',
      (pages) => [pages[2], pages[0], pages[1]],
    );

    expect(await pageTexts(path), ['Three', 'One', 'Two']);
  });

  test('deleted and duplicated pages are saved', () async {
    final path = await rearrange(
      'edit',
      (pages) => [pages[0], pages[0], pages[2]],
    );

    expect(await pageTexts(path), ['One', 'One', 'Three']);
  });

  test('a rotated page is saved rotated', () async {
    final path = await rearrange(
      'rotate',
      (pages) => [pages[0].rotatedCW90(), pages[1], pages[2]],
    );

    final document = await PdfDocument.openFile(path);
    try {
      expect(document.pages[0].rotation, PdfPageRotation.clockwise90);
      expect(document.pages[0].width, greaterThan(document.pages[0].height));
      expect(document.pages[1].rotation, PdfPageRotation.none);
    } finally {
      await document.dispose();
    }
  });

  test('pages added from another PDF are saved', () async {
    final extra = File('${temp.path}/extra.pdf')
      ..writeAsBytesSync(buildSamplePdf(['Extra']));
    final added = await PdfDocument.openFile(extra.path);
    try {
      final path = await rearrange(
        'merge',
        (pages) => [...pages, ...added.pages],
      );

      expect(await pageTexts(path), ['One', 'Two', 'Three', 'Extra']);
    } finally {
      await added.dispose();
    }
  });
}
