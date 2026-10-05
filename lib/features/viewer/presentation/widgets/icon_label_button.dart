import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// An icon with its label underneath: the buttons of the viewer's bars.
///
/// Fills the width it is given, so it is normally wrapped in [Expanded].
class IconLabelButton extends StatelessWidget {
  const IconLabelButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.textPrimary,
    this.selected = false,
  });

  final IconData icon;
  final String label;

  /// Null disables the button.
  final VoidCallback? onTap;
  final Color color;

  /// Shows the icon on a tinted pill, for the active tool.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final shown = onTap == null
        ? AppColors.textSubtle
        : selected
        ? AppColors.primary
        : color;
    return Semantics(
      button: true,
      enabled: onTap != null,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          // Comfortable to hit with a thumb
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primaryTint
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Icon(icon, size: 22, color: shown),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: shown,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dims the screen and shows a spinner while a save is in progress.
class BusyOverlay extends StatelessWidget {
  const BusyOverlay({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0x99FFFFFF),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
