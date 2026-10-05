import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/edit_marks.dart';

/// Bottom sheet where the user draws a signature. Resolves to null when
/// dismissed without one.
Future<Signature?> showSignaturePad(BuildContext context) {
  return showModalBottomSheet<Signature>(
    context: context,
    isScrollControlled: true,
    // Dragging down would fight with drawing
    enableDrag: false,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => const _SignaturePad(),
  );
}

class _SignaturePad extends StatefulWidget {
  const _SignaturePad();

  @override
  State<_SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<_SignaturePad> {
  final _strokes = <List<Offset>>[];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Draw your signature', style: text.titleLarge),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: GestureDetector(
                key: const Key('signature-canvas'),
                onPanStart: (details) =>
                    setState(() => _strokes.add([details.localPosition])),
                onPanUpdate: (details) =>
                    setState(() => _strokes.last.add(details.localPosition)),
                child: CustomPaint(
                  painter: _PadPainter(_strokes),
                  child: _strokes.isEmpty
                      ? Center(child: Text('Sign here', style: text.bodySmall))
                      : const SizedBox.expand(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _strokes.isEmpty
                        ? null
                        : () => setState(_strokes.clear),
                    child: const Text('Clear'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _strokes.isEmpty
                        ? null
                        : () =>
                              Navigator.of(context)
                                  .pop(Signature.fromPad(_strokes)),
                    child: const Text('Use signature'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter(this.strokes);

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final stroke in strokes) {
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  // The stroke list is mutated in place, so identity cannot tell
  @override
  bool shouldRepaint(_PadPainter oldDelegate) => true;
}
