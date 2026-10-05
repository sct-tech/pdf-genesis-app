import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The PDF Genesis mark: a page that is also a speech bubble, lettered
/// "PDF", with a four-point spark where a file icon would have its folded
/// corner. It reads as "ask the PDF".
///
/// Drawn on a 240 unit artboard in the style of the Stitch logo sheet (brand
/// gradient tile, white glyph, amber spark) and scaled to whatever size it is
/// painted at, so it is sharp from 16 px to 1024 px. The launcher icons are
/// rendered from this same painter by `tool/generate_app_icons.dart`.
class BrandMarkPainter extends CustomPainter {
  const BrandMarkPainter({this.tile = BrandTile.rounded, this.glyphScale = 1});

  /// What is drawn behind the glyph.
  final BrandTile tile;

  /// Size of the glyph relative to its normal size in the tile, kept centred.
  /// Android's adaptive icons crop the outer part of the canvas, so their
  /// foreground uses a smaller glyph.
  final double glyphScale;

  static const artboard = 240.0;

  /// Corner radius of the tile, as a fraction of its side.
  static const cornerRadius = 52 / artboard;

  static const spark = Color(0xFFFBBF24);

  static const _centre = Offset(artboard / 2, artboard / 2);
  static const _sparkCentre = Offset(162, 62);
  static const _pageBody = Rect.fromLTRB(42, 46, 158, 186);

  /// The page with its speech-bubble tail, minus a round bite at the top
  /// right corner that gives the spark room.
  static final Path _page = Path.combine(
    PathOperation.difference,
    Path.combine(
      PathOperation.union,
      Path()..addRRect(
        RRect.fromRectAndRadius(_pageBody, const Radius.circular(22)),
      ),
      Path()..addPolygon(const [
        Offset(62, 170),
        Offset(62, 214),
        Offset(104, 170),
      ], true),
    ),
    Path()..addOval(Rect.fromCircle(center: _sparkCentre, radius: 44)),
  );

  static final Path _spark = Path()
    ..moveTo(162, 24)
    ..cubicTo(162, 47, 177, 62, 200, 62)
    ..cubicTo(177, 62, 162, 77, 162, 100)
    ..cubicTo(162, 77, 147, 62, 124, 62)
    ..cubicTo(147, 62, 162, 47, 162, 24)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    if (tile != BrandTile.none) {
      final background = Paint()
        ..shader = AppColors.brandGradient.createShader(rect);
      if (tile == BrandTile.square) {
        canvas.drawRect(rect, background);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            rect,
            Radius.circular(size.shortestSide * cornerRadius),
          ),
          background,
        );
      }
    }

    canvas
      ..save()
      ..scale(size.width / artboard, size.height / artboard)
      ..translate(_centre.dx, _centre.dy)
      ..scale(glyphScale)
      ..translate(-_centre.dx, -_centre.dy)
      ..drawPath(_page, Paint()..color = Colors.white)
      ..drawPath(_spark, Paint()..color = spark);

    final letters = TextPainter(
      text: const TextSpan(
        text: 'PDF',
        style: TextStyle(
          fontFamily: 'PlusJakartaSans',
          fontSize: 46,
          height: 1,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
          color: AppColors.primary,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    letters
      ..paint(
        canvas,
        Offset(
          _pageBody.center.dx - letters.width / 2,
          // Optically centred in the part of the page below the spark
          136 - letters.height / 2,
        ),
      )
      ..dispose();

    canvas.restore();
  }

  @override
  bool shouldRepaint(BrandMarkPainter oldDelegate) =>
      oldDelegate.tile != tile || oldDelegate.glyphScale != glyphScale;
}

/// Background of the mark.
enum BrandTile {
  /// Gradient tile with rounded corners: the mark as shown in the app.
  rounded,

  /// Gradient to the edges, for platforms that round the corners themselves.
  square,

  /// Glyph only, on a transparent background.
  none,
}
