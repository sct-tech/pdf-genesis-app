import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/theme/app_colors.dart';

/// Navigation with exactly three tabs: a bottom bar on phones, a side rail
/// on wider windows where vertical space is worth more. There is
/// deliberately no chat tab: chat always belongs to a selected document.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _tabs = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.folder_outlined, Icons.folder_rounded, 'Documents'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  void _select(int index) => navigationShell.goBranch(
    index,
    // Tapping the current tab returns to its first screen
    initialLocation: index == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context) {
    if (WindowSize.of(context).isCompact) {
      return Scaffold(
        body: navigationShell,
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _select,
            destinations: [
              for (final (icon, selectedIcon, label) in _tabs)
                NavigationDestination(
                  icon: Icon(icon),
                  selectedIcon: Icon(selectedIcon),
                  label: label,
                ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          SafeArea(
            right: false,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(right: BorderSide(color: AppColors.border)),
              ),
              // Scrolls when a short landscape window cannot fit the tabs
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: NavigationRail(
                        selectedIndex: navigationShell.currentIndex,
                        onDestinationSelected: _select,
                        labelType: NavigationRailLabelType.all,
                        backgroundColor: AppColors.surface,
                        destinations: [
                          for (final (icon, selectedIcon, label) in _tabs)
                            NavigationRailDestination(
                              icon: Icon(icon),
                              selectedIcon: Icon(selectedIcon),
                              label: Text(label),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}
