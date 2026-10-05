import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the app's real fonts for every test. Without them Flutter lays text
/// out in its square test font, which is far wider than what a user sees, so
/// overflow checks would not reflect a real device.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final family in ['Inter', 'PlusJakartaSans']) {
    final bytes = File('assets/fonts/$family.ttf').readAsBytesSync();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
  await testMain();
}
