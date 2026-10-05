// Renders the launcher icons from the in-app brand mark, so the icon on the
// home screen and the logo inside the app can never drift apart.
//
//   flutter test tool/generate_app_icons.dart
//
// Run it again after changing `BrandMarkPainter`.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_genesis/core/widgets/brand_mark.dart';

const _androidRes = 'android/app/src/main/res';
const _iosIcons = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';

/// Android density buckets and their scale against mdpi.
const _densities = {
  'mdpi': 1.0,
  'hdpi': 1.5,
  'xhdpi': 2.0,
  'xxhdpi': 3.0,
  'xxxhdpi': 4.0,
};

/// iOS icon files and their size in pixels.
const _iosSizes = {
  'Icon-App-20x20@1x.png': 20,
  'Icon-App-20x20@2x.png': 40,
  'Icon-App-20x20@3x.png': 60,
  'Icon-App-29x29@1x.png': 29,
  'Icon-App-29x29@2x.png': 58,
  'Icon-App-29x29@3x.png': 87,
  'Icon-App-40x40@1x.png': 40,
  'Icon-App-40x40@2x.png': 80,
  'Icon-App-40x40@3x.png': 120,
  'Icon-App-60x60@2x.png': 120,
  'Icon-App-60x60@3x.png': 180,
  'Icon-App-76x76@1x.png': 76,
  'Icon-App-76x76@2x.png': 152,
  'Icon-App-83.5x83.5@2x.png': 167,
  'Icon-App-1024x1024@1x.png': 1024,
};

Future<void> _render(String path, int pixels, BrandMarkPainter painter) async {
  final recorder = ui.PictureRecorder();
  final size = Size.square(pixels.toDouble());
  painter.paint(Canvas(recorder), size);
  final image = await recorder.endRecording().toImage(pixels, pixels);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  testWidgets('generate app icons', (tester) async {
    await tester.runAsync(() async {
      // The mark's lettering uses the app's own font
      final font = File('assets/fonts/PlusJakartaSans.ttf').readAsBytesSync();
      await (FontLoader(
        'PlusJakartaSans',
      )..addFont(Future.value(ByteData.sublistView(font)))).load();

      // A large preview for reviewing the design
      await _render('build/brand_preview.png', 512, const BrandMarkPainter());

      for (final MapEntry(key: density, value: scale) in _densities.entries) {
        // Launchers before Android 8 show this file as it is
        await _render(
          '$_androidRes/mipmap-$density/ic_launcher.png',
          (48 * scale).round(),
          const BrandMarkPainter(),
        );
        // Adaptive icon foreground: a 108 dp canvas of which the launcher
        // shows the middle 72 dp, so the glyph is drawn at two thirds
        await _render(
          '$_androidRes/mipmap-$density/ic_launcher_foreground.png',
          (108 * scale).round(),
          const BrandMarkPainter(tile: BrandTile.none, glyphScale: 2 / 3),
        );
      }

      // iOS rounds the corners itself and rejects transparency
      for (final MapEntry(key: file, value: pixels) in _iosSizes.entries) {
        await _render(
          '$_iosIcons/$file',
          pixels,
          const BrandMarkPainter(tile: BrandTile.square),
        );
      }

      // Play Store listing icon
      await _render(
        'assets/brand/icon-512.png',
        512,
        const BrandMarkPainter(tile: BrandTile.square),
      );
    });
  });
}
