import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../application/edit_session.dart';
import 'widgets/icon_label_button.dart';

/// Row of tools along the bottom of the editor. Tapping the active tool
/// releases it so the page can be scrolled with one finger again.
class EditToolBar extends StatelessWidget {
  const EditToolBar({super.key, required this.session, required this.onSelect});

  final EditSession session;
  final ValueChanged<EditTool> onSelect;

  static const _tools = [
    (EditTool.pen, Icons.edit_outlined, 'Pen'),
    (EditTool.highlight, Icons.border_color_outlined, 'Highlight'),
    (EditTool.text, Icons.title_rounded, 'Text'),
    (EditTool.sign, Icons.draw_outlined, 'Sign'),
    (EditTool.eraser, Icons.auto_fix_normal_outlined, 'Eraser'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => Row(
        children: [
          for (final (tool, icon, label) in _tools)
            Expanded(
              child: IconLabelButton(
                icon: icon,
                label: label,
                color: AppColors.textSecondary,
                selected: session.tool == tool,
                onTap: () => onSelect(tool),
              ),
            ),
        ],
      ),
    );
  }
}

/// Colour, size and per-tool actions for the active tool.
class EditOptionsStrip extends StatefulWidget {
  const EditOptionsStrip({
    super.key,
    required this.session,
    required this.onNewSignature,
  });

  final EditSession session;
  final VoidCallback onNewSignature;

  @override
  State<EditOptionsStrip> createState() => _EditOptionsStripState();
}

class _EditOptionsStripState extends State<EditOptionsStrip> {
  // First change of a slider drag opens an undo step, the rest join it
  bool _dragStart = false;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final tool = session.tool;
        if (tool == null) return const SizedBox.shrink();
        final text = Theme.of(context).textTheme;

        final Widget content;
        if (tool == EditTool.eraser) {
          content = Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'Tap or drag over a mark to remove it.',
              style: text.bodySmall,
            ),
          );
        } else {
          final (min, max) = session.sizeRange;
          final selected = session.selected;
          final sizeLabel = tool == EditTool.pen || tool == EditTool.highlight
              ? 'Thickness'
              : 'Size';
          content = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // The colours scroll so the actions beside them always
                  // fit, whatever the screen width
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final color in session.palette)
                            _Swatch(
                              color: color,
                              selected: color == session.color,
                              onTap: () => session.setColor(color),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (tool == EditTool.sign)
                    TextButton(
                      onPressed: widget.onNewSignature,
                      child: const Text('New'),
                    ),
                  if (selected != null)
                    IconButton(
                      tooltip: 'Delete',
                      onPressed: () => session.remove(selected),
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.danger,
                      ),
                    ),
                ],
              ),
              Row(
                children: [
                  Text(sizeLabel, style: text.bodySmall),
                  Expanded(
                    child: Slider(
                      min: min,
                      max: max,
                      value: session.size.clamp(min, max),
                      semanticFormatterCallback: (value) {
                        final percent = (value - min) / (max - min) * 100;
                        return '$sizeLabel ${percent.round()} percent';
                      },
                      onChangeStart: (_) => _dragStart = true,
                      onChanged: (value) {
                        session.setSize(value, record: _dragStart);
                        _dragStart = false;
                      },
                    ),
                  ),
                ],
              ),
            ],
          );
        }

        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x140F172A),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: content,
        );
      },
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: EditSession.colorName(color),
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox(
          // The dot is small; the tap target around it is not
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              padding: const EdgeInsets.all(3),
              child: DecoratedBox(
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
