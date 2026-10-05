import 'dart:convert';

import 'package:flutter/painting.dart';

/// An edit drawn on a page that has not been written into the PDF yet.
///
/// All geometry is normalised to the page as it is displayed: (0, 0) is the
/// top-left corner and (1, 1) the bottom-right, so marks are independent of
/// zoom. Lengths that are not points are fractions of the page width.
sealed class EditMark {
  const EditMark({required this.id, required this.page});

  final int id;

  /// 1-based page number.
  final int page;

  /// Bounds in normalised page coordinates, used for hit testing.
  Rect get bounds;
}

/// A freehand line from the pen or the highlighter.
class StrokeMark extends EditMark {
  StrokeMark({
    required super.id,
    required super.page,
    required this.points,
    required this.color,
    required this.width,
    this.highlighter = false,
  });

  /// The session appends to this list while the stroke is being drawn; it
  /// does not change once the stroke is part of the session's marks.
  final List<Offset> points;
  final Color color;

  /// Line width as a fraction of the page width.
  final double width;

  /// Highlighter strokes are see-through and darken what is beneath them.
  final bool highlighter;

  @override
  late final Rect bounds = () {
    var rect = Rect.fromPoints(points.first, points.first);
    for (final point in points) {
      rect = rect.expandToInclude(Rect.fromPoints(point, point));
    }
    return rect.inflate(width / 2);
  }();
}

/// A typed note. [position] is the top-left corner of the first line.
class TextMark extends EditMark {
  TextMark({
    required super.id,
    required super.page,
    required this.position,
    required this.text,
    required this.color,
    required this.size,
    this.pageAspectRatio = 1,
  });

  final Offset position;
  final String text;
  final Color color;

  /// Font size as a fraction of the page width.
  final double size;

  /// Page width divided by page height, needed to normalise the text height.
  final double pageAspectRatio;

  /// The text as it is written into the PDF when [isSelectableInPdf].
  String get pdfText => plainPunctuation(text);

  /// Whether the note can be saved as real, searchable text. Only Latin-1
  /// can: the standard PDF fonts cover nothing else. Other notes are saved
  /// as an image of the text instead.
  bool get isSelectableInPdf => pdfText.runes.every((rune) => rune <= 0xFF);

  /// Line height as a multiple of the font size, shared with the PDF writer.
  static const lineHeight = 1.25;

  /// The style the editor previews a note with at [fontSize] pixels.
  static TextStyle style(double fontSize, Color color) => TextStyle(
    fontFamily: 'Inter',
    fontSize: fontSize,
    height: lineHeight,
    color: color,
  );

  static TextPainter _layout(String text, double fontSize, Color color) =>
      TextPainter(
        text: TextSpan(text: text, style: style(fontSize, color)),
        textDirection: TextDirection.ltr,
      )..layout();

  /// Distance from the top of a line to its baseline, as a multiple of the
  /// font size. The PDF writer needs it to match the preview.
  static double get baselineRatio {
    const probe = 100.0;
    final painter = _layout('Ag', probe, const Color(0xFF000000));
    final baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    painter.dispose();
    return baseline / probe;
  }

  TextMark copyWith({
    Offset? position,
    String? text,
    Color? color,
    double? size,
  }) => TextMark(
    id: id,
    page: page,
    position: position ?? this.position,
    text: text ?? this.text,
    color: color ?? this.color,
    size: size ?? this.size,
    pageAspectRatio: pageAspectRatio,
  );

  @override
  late final Rect bounds = () {
    // Measured on a page 1000 px wide; the result is normalised so the
    // reference width drops out
    const reference = 1000.0;
    final painter = _layout(text, size * reference, color);
    final extent = Size(
      painter.width / reference,
      painter.height / reference * pageAspectRatio,
    );
    painter.dispose();
    return position & extent;
  }();
}

/// A hand-drawn signature placed inside [rect].
class SignatureMark extends EditMark {
  const SignatureMark({
    required super.id,
    required super.page,
    required this.rect,
    required this.signature,
    required this.color,
  });

  final Rect rect;
  final Signature signature;
  final Color color;

  SignatureMark copyWith({Rect? rect, Color? color}) => SignatureMark(
    id: id,
    page: page,
    rect: rect ?? this.rect,
    signature: signature,
    color: color ?? this.color,
  );

  @override
  Rect get bounds => rect;
}

/// Strokes of a signature, each point normalised to the signature's own box.
class Signature {
  const Signature({required this.strokes, required this.aspectRatio});

  /// Builds a signature from raw pad strokes, cropped to what was drawn.
  factory Signature.fromPad(List<List<Offset>> padStrokes) {
    final all = padStrokes.expand((stroke) => stroke);
    var box = Rect.fromPoints(all.first, all.first);
    for (final point in all) {
      box = box.expandToInclude(Rect.fromPoints(point, point));
    }
    // A dot or a straight line still needs a box with some area
    final width = box.width < 1 ? 1.0 : box.width;
    final height = box.height < 1 ? 1.0 : box.height;
    return Signature(
      aspectRatio: width / height,
      strokes: [
        for (final stroke in padStrokes)
          [
            for (final point in stroke)
              Offset(
                (point.dx - box.left) / width,
                (point.dy - box.top) / height,
              ),
          ],
      ],
    );
  }

  factory Signature.fromJson(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    return Signature(
      aspectRatio: (json['aspectRatio'] as num).toDouble(),
      strokes: [
        for (final stroke in json['strokes'] as List<dynamic>)
          [
            for (final point in stroke as List<dynamic>)
              Offset(
                ((point as List<dynamic>)[0] as num).toDouble(),
                (point[1] as num).toDouble(),
              ),
          ],
      ],
    );
  }

  final List<List<Offset>> strokes;

  /// Width divided by height of the drawn signature.
  final double aspectRatio;

  String toJson() => jsonEncode({
    'aspectRatio': aspectRatio,
    'strokes': [
      for (final stroke in strokes)
        [
          for (final point in stroke) [point.dx, point.dy],
        ],
    ],
  });
}

/// Signature line width as a fraction of the signature's own width.
const signatureStrokeWidth = 0.012;

/// Swaps the typographic punctuation phone keyboards insert for the plain
/// characters the standard PDF fonts can draw.
String plainPunctuation(String text) => text
    .replaceAll(RegExp('[\u2018\u2019\u201A\u2032]'), "'")
    .replaceAll(RegExp('[\u201C\u201D\u201E\u2033]'), '"')
    .replaceAll(RegExp('[\u2010-\u2015]'), '-')
    .replaceAll('\u2026', '...')
    .replaceAll('\u00A0', ' ');
