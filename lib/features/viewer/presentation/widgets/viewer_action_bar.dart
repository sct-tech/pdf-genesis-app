import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'icon_label_button.dart';

/// Floating bar of the viewer: Pages, Edit, Share and Ask AI.
class ViewerActionBar extends StatelessWidget {
  const ViewerActionBar({
    super.key,
    required this.onPages,
    required this.onEdit,
    required this.onShare,
    required this.onAskAi,
  });

  final VoidCallback onPages;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onAskAi;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A0F172A),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: const BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: IconLabelButton(
                  icon: Icons.grid_view_rounded,
                  label: 'Pages',
                  onTap: onPages,
                ),
              ),
              Expanded(
                child: IconLabelButton(
                  icon: Icons.edit_outlined,
                  label: 'Edit',
                  onTap: onEdit,
                ),
              ),
              Expanded(
                child: IconLabelButton(
                  icon: Icons.ios_share_rounded,
                  label: 'Share',
                  onTap: onShare,
                ),
              ),
              const SizedBox(width: 6),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: const StadiumBorder(),
                ),
                onPressed: onAskAi,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Ask AI'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small pill showing the current page over the document.
class PageIndicator extends StatelessWidget {
  const PageIndicator({super.key, required this.page, required this.count});

  final int page;
  final int count;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xD90F172A),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          'Page $page of $count',
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}
