import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

var _assembled = 0;

/// Builds a new PDF made of [pages], in that order. Pages may come from any
/// open document, may repeat, and may carry a new rotation.
///
/// The pages are copied into an empty document rather than rearranged in the
/// one they came from: pdfrx 2.6 skips the rearrangement when every page
/// stays in its own document, so a pure reorder would be saved unchanged.
Future<Uint8List> assemblePages(List<PdfPage> pages) async {
  await pdfrxFlutterInitialize();
  final output = await PdfDocument.createNew(
    // Must be unique per document or pdfrx may mix them up
    sourceName: 'assembled:${_assembled++}',
  );
  try {
    output.pages = pages;
    return await output.encodePdf();
  } finally {
    await output.dispose();
  }
}
