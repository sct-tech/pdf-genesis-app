import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Window width classes, after the Material 3 breakpoints.
enum WindowSize {
  /// Phones in portrait.
  compact,

  /// Large phones in landscape, small tablets, foldables.
  medium,

  /// Tablets in landscape and desktop windows.
  expanded;

  static const mediumBreakpoint = 600.0;
  static const expandedBreakpoint = 840.0;

  factory WindowSize.fromWidth(double width) => width >= expandedBreakpoint
      ? WindowSize.expanded
      : width >= mediumBreakpoint
      ? WindowSize.medium
      : WindowSize.compact;

  /// The class of the whole window. Rebuilds the caller when the width
  /// changes (rotation, split screen, a foldable opening).
  static WindowSize of(BuildContext context) =>
      WindowSize.fromWidth(MediaQuery.sizeOf(context).width);

  bool get isCompact => this == WindowSize.compact;
}

/// Widest a column of content should grow before it is centred instead.
abstract final class ContentWidths {
  /// Forms and reading text: a comfortable line length.
  static const reading = 640.0;

  /// A conversation.
  static const chat = 760.0;

  /// Lists and grids of cards.
  static const wide = 1080.0;

  /// Floating tool bars.
  static const toolbar = 520.0;
}

/// Centres [child] and stops it growing past [maxWidth], so a phone layout
/// does not stretch edge to edge on a tablet.
class ContentWidth extends StatelessWidget {
  /// For a screen body: fills the height it is given.
  const ContentWidth({
    super.key,
    required this.child,
    this.maxWidth = ContentWidths.reading,
  }) : _fillHeight = true;

  /// For a tool bar: only as tall as [child]. A bar that filled the height
  /// would take the whole screen when used as a bottom navigation bar.
  const ContentWidth.bar({
    super.key,
    required this.child,
    this.maxWidth = ContentWidths.toolbar,
  }) : _fillHeight = false;

  final Widget child;
  final double maxWidth;
  final bool _fillHeight;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      heightFactor: _fillHeight ? null : 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Lays [children] out in as many equal columns as fit, each at least
/// [minItemWidth] wide: one column on a phone, more on a tablet.
///
/// Not lazy, so meant for short lists.
class AdaptiveGrid extends StatelessWidget {
  const AdaptiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 340,
    this.spacing = 12,
  });

  final List<Widget> children;
  final double minItemWidth;
  final double spacing;

  /// Columns that fit in [width].
  static int columnsFor(double width, double minItemWidth, double spacing) =>
      math.max(1, ((width + spacing) / (minItemWidth + spacing)).floor());

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsFor(constraints.maxWidth, minItemWidth, spacing);
        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              // Floored so rounding never pushes the last column to a new row
              SizedBox(width: itemWidth.floorToDouble(), child: child),
          ],
        );
      },
    );
  }
}
