import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../data/edit_marks.dart';

enum EditTool { pen, highlight, text, sign, eraser }

/// Marks drawn in the editor that are not saved yet, with undo and redo.
///
/// Notifies on every change, including each point of a stroke in progress,
/// so page overlays can repaint without rebuilding the viewer.
class EditSession extends ChangeNotifier {
  static const penColors = [
    Color(0xFF0F172A),
    Color(0xFF2563EB),
    Color(0xFFDC2626),
    Color(0xFF16A34A),
    Color(0xFFF59E0B),
    Color(0xFF7C3AED),
  ];

  static const highlightColors = [
    Color(0xFFFACC15),
    Color(0xFF4ADE80),
    Color(0xFFF472B6),
    Color(0xFF38BDF8),
    Color(0xFFFB923C),
  ];

  static const _colorNames = {
    0xFF0F172A: 'Black',
    0xFF2563EB: 'Blue',
    0xFFDC2626: 'Red',
    0xFF16A34A: 'Green',
    0xFFF59E0B: 'Amber',
    0xFF7C3AED: 'Purple',
    0xFFFACC15: 'Yellow',
    0xFF4ADE80: 'Light green',
    0xFFF472B6: 'Pink',
    0xFF38BDF8: 'Light blue',
    0xFFFB923C: 'Orange',
  };

  /// What a screen reader calls a palette colour.
  static String colorName(Color color) =>
      _colorNames[color.toARGB32()] ?? 'Colour';

  static const _highlightOpacity = 0.4;

  // Fractions of the page width
  static const minPenWidth = 0.002;
  static const maxPenWidth = 0.012;
  static const minHighlightWidth = 0.015;
  static const maxHighlightWidth = 0.05;
  static const minTextSize = 0.018;
  static const maxTextSize = 0.07;
  static const minSignatureWidth = 0.12;
  static const maxSignatureWidth = 0.8;

  List<EditMark> _marks = const [];
  final _undo = <List<EditMark>>[];
  final _redo = <List<EditMark>>[];
  var _nextId = 1;

  EditTool? _tool;
  StrokeMark? _draft;
  int? _selectedId;

  // Style of each tool. Changed through [setColor] and [setSize] only, so
  // the options strip is always told.
  Color _penColor = penColors[1];
  double _penWidth = 0.004;
  Color _highlightColor = highlightColors[0];
  double _highlightWidth = 0.028;
  Color _textColor = penColors[2];
  double _textSize = 0.03;
  Color _signatureColor = penColors[0];
  double _signatureWidth = 0.35;

  List<EditMark> get marks => _marks;

  /// The stroke being drawn, not yet part of [marks].
  StrokeMark? get draft => _draft;

  /// The tool in use, or null while the viewer is free to scroll and zoom.
  EditTool? get tool => _tool;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get hasChanges => _marks.isNotEmpty;

  /// True when saving adds readable text to the PDF. Notes saved as images
  /// and drawings leave the text as it was.
  bool get changesText =>
      _marks.any((mark) => mark is TextMark && mark.isSelectableInPdf);

  /// The text note or signature the options strip is editing.
  EditMark? get selected {
    for (final mark in _marks) {
      if (mark.id == _selectedId) return mark;
    }
    return null;
  }

  Iterable<EditMark> marksOn(int page) =>
      _marks.where((mark) => mark.page == page);

  set tool(EditTool? value) {
    _tool = value;
    _draft = null;
    _selectedId = null;
    notifyListeners();
  }

  void select(EditMark? mark) {
    _selectedId = mark?.id;
    // The options strip should show the selected mark's own style
    switch (mark) {
      case TextMark():
        _textSize = mark.size;
        _textColor = mark.color;
      case SignatureMark():
        _signatureWidth = mark.rect.width;
        _signatureColor = mark.color;
      default:
        break;
    }
    notifyListeners();
  }

  void _commit(List<EditMark> next) {
    _undo.add(_marks);
    _redo.clear();
    _marks = next;
    notifyListeners();
  }

  void undo() {
    if (!canUndo) return;
    _redo.add(_marks);
    _marks = _undo.removeLast();
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    _undo.add(_marks);
    _marks = _redo.removeLast();
    notifyListeners();
  }

  void clear() {
    _marks = const [];
    _undo.clear();
    _redo.clear();
    _draft = null;
    _selectedId = null;
    notifyListeners();
  }

  // Options of the active tool. Changing them also restyles the selected
  // text note or signature.

  List<Color> get palette =>
      _tool == EditTool.highlight ? highlightColors : penColors;

  Color get color => switch (_tool) {
    EditTool.highlight => _highlightColor,
    EditTool.text => _textColor,
    EditTool.sign => _signatureColor,
    _ => _penColor,
  };

  /// Smallest and largest value of [size] for the active tool.
  (double, double) get sizeRange => switch (_tool) {
    EditTool.highlight => (minHighlightWidth, maxHighlightWidth),
    EditTool.text => (minTextSize, maxTextSize),
    EditTool.sign => (minSignatureWidth, maxSignatureWidth),
    _ => (minPenWidth, maxPenWidth),
  };

  double get size => switch (_tool) {
    EditTool.highlight => _highlightWidth,
    EditTool.text => _textSize,
    EditTool.sign => _signatureWidth,
    _ => _penWidth,
  };

  void setColor(Color value) {
    final mark = selected;
    switch (_tool) {
      case EditTool.highlight:
        _highlightColor = value;
      case EditTool.text:
        _textColor = value;
        if (mark is TextMark) return replace(mark, mark.copyWith(color: value));
      case EditTool.sign:
        _signatureColor = value;
        if (mark is SignatureMark) {
          return replace(mark, mark.copyWith(color: value));
        }
      default:
        _penColor = value;
    }
    notifyListeners();
  }

  /// With [record] false the change joins the previous undo step, which
  /// keeps one slider drag as one step.
  void setSize(double value, {bool record = true}) {
    final mark = selected;
    switch (_tool) {
      case EditTool.highlight:
        _highlightWidth = value;
      case EditTool.text:
        _textSize = value;
        if (mark is TextMark) {
          return replace(mark, mark.copyWith(size: value), record: record);
        }
      case EditTool.sign:
        _signatureWidth = value;
        if (mark is SignatureMark) {
          final rect = mark.rect;
          final resized = Rect.fromCenter(
            center: rect.center,
            width: value,
            height: rect.height * value / rect.width,
          );
          return replace(mark, mark.copyWith(rect: resized), record: record);
        }
      default:
        _penWidth = value;
    }
    notifyListeners();
  }

  // Strokes

  void startStroke(int page, Offset point) {
    final highlighter = _tool == EditTool.highlight;
    _draft = StrokeMark(
      id: _nextId++,
      page: page,
      points: [point],
      width: highlighter ? _highlightWidth : _penWidth,
      color: highlighter
          ? _highlightColor.withValues(alpha: _highlightOpacity)
          : _penColor,
      highlighter: highlighter,
    );
    notifyListeners();
  }

  void extendStroke(Offset point) {
    final draft = _draft;
    if (draft == null) return;
    draft.points.add(point);
    notifyListeners();
  }

  void endStroke() {
    final draft = _draft;
    if (draft == null) return;
    _draft = null;
    _commit([..._marks, draft]);
  }

  /// Drops the stroke in progress, e.g. when a second finger starts a pinch.
  void cancelStroke() {
    if (_draft == null) return;
    _draft = null;
    notifyListeners();
  }

  // Text notes and signatures

  /// [pageAspectRatio] is the page's width divided by its height.
  void addText(int page, Offset position, String text, double pageAspectRatio) {
    final mark = TextMark(
      id: _nextId++,
      page: page,
      position: position,
      text: text,
      color: _textColor,
      size: _textSize,
      pageAspectRatio: pageAspectRatio,
    );
    _selectedId = mark.id;
    _commit([..._marks, mark]);
  }

  /// Places [signature] centred on [center]. [pageAspectRatio] is the page's
  /// width divided by its height.
  void addSignature(
    int page,
    Offset center,
    Signature signature,
    double pageAspectRatio,
  ) {
    final width = _signatureWidth;
    final height = width / signature.aspectRatio * pageAspectRatio;
    final mark = SignatureMark(
      id: _nextId++,
      page: page,
      rect: Rect.fromCenter(center: center, width: width, height: height),
      signature: signature,
      color: _signatureColor,
    );
    _selectedId = mark.id;
    _commit([..._marks, mark]);
  }

  /// Swaps [mark] for [replacement]. With [record] false the change joins
  /// the previous undo step, which keeps a drag as one step.
  void replace(EditMark mark, EditMark replacement, {bool record = true}) {
    final next = [
      for (final existing in _marks)
        if (existing.id == mark.id) replacement else existing,
    ];
    if (record) {
      _commit(next);
    } else {
      _marks = next;
      notifyListeners();
    }
  }

  void remove(EditMark mark) {
    if (_selectedId == mark.id) _selectedId = null;
    _commit(_marks.where((existing) => existing.id != mark.id).toList());
  }

  /// Topmost mark under [point] on [page]. [slop] widens thin strokes so
  /// they can be hit with a finger.
  EditMark? hitTest(
    int page,
    Offset point, {
    double slop = 0.02,
    bool Function(EditMark mark)? where,
  }) {
    for (final mark in _marks.reversed) {
      if (mark.page != page || (where != null && !where(mark))) continue;
      if (!mark.bounds.inflate(slop).contains(point)) continue;
      if (mark is! StrokeMark) return mark;
      final reach = mark.width / 2 + slop;
      if (_distanceToStroke(mark.points, point) <= reach) return mark;
    }
    return null;
  }

  static double _distanceToStroke(List<Offset> points, Offset point) {
    var nearest = (points.first - point).distance;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final segment = points[i] - a;
      final lengthSquared = segment.distanceSquared;
      final t = lengthSquared == 0
          ? 0.0
          : (((point.dx - a.dx) * segment.dx + (point.dy - a.dy) * segment.dy) /
                    lengthSquared)
                .clamp(0.0, 1.0);
      final distance = (a + segment * t - point).distance;
      if (distance < nearest) nearest = distance;
    }
    return nearest;
  }
}
