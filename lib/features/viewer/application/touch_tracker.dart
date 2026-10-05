/// Counts the fingers on the viewer across every page layer.
///
/// One finger edits; a second finger means pinch-zoom, which belongs to the
/// viewer. Each page layer only sees the touches that land on it, so the
/// count has to be shared: the two fingers of a pinch are often on different
/// pages.
class TouchTracker {
  final _pointers = <int>{};
  bool _multiTouch = false;

  /// True from the moment a second finger lands until every finger is up.
  /// Edits are suspended for the whole of that time, so the finger that
  /// stays down after a pinch cannot go on drawing or erasing.
  bool get isMultiTouch => _multiTouch;

  /// Records a finger landing. Returns true when it starts a one-finger
  /// gesture that may edit.
  bool down(int pointer) {
    _pointers.add(pointer);
    if (_pointers.length > 1) _multiTouch = true;
    return !_multiTouch;
  }

  /// Records a finger lifting. Returns true when the gesture it ends was a
  /// one-finger gesture from start to finish.
  bool up(int pointer) {
    _pointers.remove(pointer);
    final single = !_multiTouch;
    if (_pointers.isEmpty) _multiTouch = false;
    return single;
  }
}
