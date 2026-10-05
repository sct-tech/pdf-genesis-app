import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../application/edit_session.dart';
import '../application/touch_tracker.dart';
import '../data/edit_marks.dart';

/// Called when the text tool is tapped. [existing] is the note under the
/// finger, or null to create one at [position].
typedef TextRequest = void Function(
  int page,
  Offset position,
  double pageAspectRatio,
  TextMark? existing,
);

/// Called when the sign tool is tapped on an empty spot of a page.
typedef SignatureRequest = void Function(
  int page,
  Offset position,
  double pageAspectRatio,
);

/// Sits on top of one page in the viewer: paints the unsaved marks and, while
/// a tool is active, turns touches into edits.
class PageEditLayer extends StatefulWidget {
  const PageEditLayer({
    super.key,
    required this.page,
    required this.session,
    required this.touches,
    required this.onTextRequested,
    required this.onSignatureRequested,
  });

  /// 1-based page number.
  final int page;
  final EditSession session;

  /// Shared by every page layer of the viewer.
  final TouchTracker touches;
  final TextRequest onTextRequested;
  final SignatureRequest onSignatureRequested;

  @override
  State<PageEditLayer> createState() => _PageEditLayerState();
}

class _PageEditLayerState extends State<PageEditLayer> {
  // Movement below this many logical pixels still counts as a tap
  static const _tapSlop = 8.0;

  Size _size = Size.zero;
  Offset? _downAt;
  bool _moved = false;

  /// Text note or signature being dragged, and the finger's offset inside it.
  EditMark? _dragging;
  Offset _grip = Offset.zero;
  bool _dragRecorded = false;

  EditSession get _session => widget.session;

  Offset _normalise(Offset local) =>
      Offset(local.dx / _size.width, local.dy / _size.height);

  double get _aspectRatio => _size.width / _size.height;

  bool _isMovable(EditMark mark) => switch (_session.tool) {
    EditTool.text => mark is TextMark,
    EditTool.sign => mark is SignatureMark,
    _ => false,
  };

  void _onDown(PointerDownEvent event) {
    if (!widget.touches.down(event.pointer)) {
      // A second finger means pinch-zoom: hand the gesture to the viewer
      _abandonGesture();
      return;
    }

    final point = _normalise(event.localPosition);
    _downAt = event.localPosition;
    _moved = false;
    switch (_session.tool) {
      case EditTool.pen || EditTool.highlight:
        _session.startStroke(widget.page, point);
      case EditTool.eraser:
        _erase(point);
      case EditTool.text || EditTool.sign:
        final mark = _session.hitTest(widget.page, point, where: _isMovable);
        _dragging = mark;
        _dragRecorded = false;
        if (mark != null) {
          _grip = point - mark.bounds.topLeft;
          _session.select(mark);
        }
      case null:
        break;
    }
  }

  void _onMove(PointerMoveEvent event) {
    // The second finger may be on another page, so this layer was not told
    // when it landed
    if (widget.touches.isMultiTouch) return _abandonGesture();
    final downAt = _downAt;
    if (downAt == null) return;
    if ((event.localPosition - downAt).distance > _tapSlop) _moved = true;

    final point = _normalise(event.localPosition);
    switch (_session.tool) {
      case EditTool.pen || EditTool.highlight:
        _session.extendStroke(point);
      case EditTool.eraser:
        _erase(point);
      case EditTool.text || EditTool.sign:
        final mark = _dragging;
        if (mark == null || !_moved) return;
        final topLeft = point - _grip;
        final moved = switch (mark) {
          TextMark() => mark.copyWith(position: topLeft),
          SignatureMark() => mark.copyWith(rect: topLeft & mark.rect.size),
          StrokeMark() => mark,
        };
        // The whole drag is one undo step
        _session.replace(mark, moved, record: !_dragRecorded);
        _dragRecorded = true;
        _dragging = moved;
      case null:
        break;
    }
  }

  void _onUp(PointerEvent event) {
    final wasSingle = widget.touches.up(event.pointer);
    final downAt = _downAt;
    if (downAt == null || !wasSingle || event is PointerCancelEvent) {
      return _abandonGesture();
    }
    _downAt = null;

    final point = _normalise(downAt);
    switch (_session.tool) {
      case EditTool.pen || EditTool.highlight:
        _session.endStroke();
      case EditTool.text when !_moved:
        final mark = _dragging;
        widget.onTextRequested(
          widget.page,
          point,
          _aspectRatio,
          mark is TextMark ? mark : null,
        );
      case EditTool.sign when !_moved && _dragging == null:
        widget.onSignatureRequested(widget.page, point, _aspectRatio);
      default:
        break;
    }
    _dragging = null;
  }

  /// Drops whatever this layer was in the middle of, leaving no edit behind.
  void _abandonGesture() {
    _session.cancelStroke();
    _downAt = null;
    _dragging = null;
  }

  void _erase(Offset point) {
    final mark = _session.hitTest(widget.page, point);
    if (mark != null) _session.remove(mark);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        return ListenableBuilder(
          listenable: _session,
          builder: (context, child) {
            final active = _session.tool != null;
            return IgnorePointer(
              ignoring: !active,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onDown,
                onPointerMove: _onMove,
                onPointerUp: _onUp,
                onPointerCancel: _onUp,
                child: child,
              ),
            );
          },
          child: CustomPaint(
            size: Size.infinite,
            painter: _MarksPainter(page: widget.page, session: _session),
          ),
        );
      },
    );
  }
}

class _MarksPainter extends CustomPainter {
  _MarksPainter({required this.page, required this.session})
    : super(repaint: session);

  final int page;
  final EditSession session;

  @override
  void paint(Canvas canvas, Size size) {
    Offset at(Offset point) =>
        Offset(point.dx * size.width, point.dy * size.height);

    // Highlighter strokes are previewed as plain see-through colour. The
    // saved PDF uses a multiply blend, which cannot be previewed here because
    // this layer is composited separately from the page beneath it.
    void stroke(List<Offset> points, Color color, double width) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      if (points.length == 1) {
        canvas.drawPoints(PointMode.points, [at(points.first)], paint);
        return;
      }
      final path = Path()..moveTo(at(points.first).dx, at(points.first).dy);
      for (final point in points.skip(1)) {
        path.lineTo(at(point).dx, at(point).dy);
      }
      canvas.drawPath(path, paint);
    }

    void paintMark(EditMark mark) {
      switch (mark) {
        case StrokeMark():
          stroke(mark.points, mark.color, mark.width * size.width);
        case TextMark():
          final painter = TextPainter(
            text: TextSpan(
              text: mark.text,
              style: TextMark.style(mark.size * size.width, mark.color),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          painter
            ..paint(canvas, at(mark.position))
            ..dispose();
        case SignatureMark(:final rect):
          for (final points in mark.signature.strokes) {
            stroke(
              [
                for (final point in points)
                  Offset(
                    rect.left + point.dx * rect.width,
                    rect.top + point.dy * rect.height,
                  ),
              ],
              mark.color,
              signatureStrokeWidth * rect.width * size.width,
            );
          }
      }
    }

    session.marksOn(page).forEach(paintMark);
    final draft = session.draft;
    if (draft != null && draft.page == page) paintMark(draft);

    final selected = session.selected;
    if (selected != null && selected.page == page) {
      final bounds = selected.bounds;
      final box = Rect.fromPoints(
        at(bounds.topLeft),
        at(bounds.bottomRight),
      ).inflate(4);
      _dashedRect(canvas, box);
    }
  }

  void _dashedRect(Canvas canvas, Rect rect) {
    const dash = 5.0;
    final paint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    void line(Offset from, Offset to) {
      final length = (to - from).distance;
      final step = (to - from) / length;
      for (var d = 0.0; d < length; d += dash * 2) {
        final end = (d + dash).clamp(0.0, length);
        canvas.drawLine(from + step * d, from + step * end, paint);
      }
    }

    line(rect.topLeft, rect.topRight);
    line(rect.topRight, rect.bottomRight);
    line(rect.bottomRight, rect.bottomLeft);
    line(rect.bottomLeft, rect.topLeft);
  }

  @override
  bool shouldRepaint(_MarksPainter oldDelegate) =>
      oldDelegate.page != page || oldDelegate.session != session;
}
