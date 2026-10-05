import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_genesis/features/viewer/application/touch_tracker.dart';

void main() {
  test('one finger down and up is a one-finger gesture', () {
    final touches = TouchTracker();

    expect(touches.down(1), isTrue);
    expect(touches.isMultiTouch, isFalse);
    expect(touches.up(1), isTrue);
  });

  test('a second finger turns the gesture into a pinch for both fingers', () {
    final touches = TouchTracker()..down(1);

    expect(touches.down(2), isFalse);
    expect(touches.isMultiTouch, isTrue);
  });

  test('the finger left down after a pinch still cannot edit', () {
    final touches = TouchTracker()
      ..down(1)
      ..down(2);

    expect(touches.up(2), isFalse);
    expect(touches.isMultiTouch, isTrue);
    expect(touches.up(1), isFalse);
  });

  test('editing is possible again once every finger is up', () {
    final touches = TouchTracker()
      ..down(1)
      ..down(2)
      ..up(1)
      ..up(2);

    expect(touches.isMultiTouch, isFalse);
    expect(touches.down(3), isTrue);
  });
}
