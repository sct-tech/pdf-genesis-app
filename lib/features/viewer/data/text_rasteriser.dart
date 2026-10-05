import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'edit_marks.dart';

/// A text note drawn to pixels, ready to be placed on a page as an image.
class RasterisedText {
  const RasterisedText({
    required this.bgra,
    required this.width,
    required this.height,
    required this.bounds,
  });

  /// Pixels in the byte order PDFium expects, alpha not premultiplied.
  final Uint8List bgra;
  final int width;
  final int height;

  /// Where the image goes on the page, in normalised page coordinates.
  final Rect bounds;
}

// Pixels across a full page width: about 290 dpi on A4, sharp when zoomed in
const _pageWidthPixels = 2400.0;

// Keeps a long note in a large font from producing a huge image
const _maxSidePixels = 4096;

/// Draws [mark] exactly as the editor previews it.
///
/// Flutter shapes the text, so every script the device has a font for comes
/// out right, including ones that need ligatures or right-to-left layout
/// (Devanagari, Gujarati, Arabic), which the standard PDF fonts cannot draw.
Future<RasterisedText> rasteriseText(TextMark mark) async {
  TextPainter layout(double scale) => TextPainter(
    text: TextSpan(
      text: mark.text,
      style: TextMark.style(mark.size * _pageWidthPixels * scale, mark.color),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  var painter = layout(1);
  final longSide = painter.width > painter.height
      ? painter.width
      : painter.height;
  if (longSide > _maxSidePixels) {
    painter.dispose();
    painter = layout(_maxSidePixels / longSide);
  }

  final width = painter.width.ceil().clamp(1, _maxSidePixels);
  final height = painter.height.ceil().clamp(1, _maxSidePixels);
  final recorder = ui.PictureRecorder();
  painter
    ..paint(Canvas(recorder), Offset.zero)
    ..dispose();
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();

  final ByteData? data;
  try {
    data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  } finally {
    image.dispose();
  }
  if (data == null) {
    throw StateError('Could not read the pixels of a rendered text note');
  }

  // RGBA -> BGRA
  final pixels = data.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  for (var i = 0; i < pixels.length; i += 4) {
    final red = pixels[i];
    pixels[i] = pixels[i + 2];
    pixels[i + 2] = red;
  }

  return RasterisedText(
    bgra: pixels,
    width: width,
    height: height,
    bounds: mark.bounds,
  );
}
