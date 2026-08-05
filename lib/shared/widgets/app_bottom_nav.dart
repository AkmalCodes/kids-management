import 'package:flutter/material.dart';

// A "floating" bottom navigation bar: inset from the screen edges with
// rounded corners and a soft shadow, so it reads as a hovering pill.
//
// It takes the same NavigationDestination list as Material's NavigationBar,
// but renders the items itself. The reason: NavigationBar's selection
// indicator is a fixed 64x32 pill (hardcoded in the framework, not
// themeable), which looks too wide in this slim floated bar. Here the
// highlight is a small rounded square that just hugs the icon.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        // Small gap on all sides so the bar hovers off the edges.
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Material(
              color: scheme.primaryContainer,
              child: SizedBox(
                height: 60,
                child: Row(
                  children: [
                    for (var i = 0; i < destinations.length; i++)
                      Expanded(
                        child: _NavItem(
                          destination: destinations[i],
                          selected: i == selectedIndex,
                          scheme: scheme,
                          onTap: () => onDestinationSelected(i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.scheme,
    required this.onTap,
  });

  final NavigationDestination destination;
  final bool selected;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return InkResponse(
      onTap: onTap,
      radius: 32,
      containedInkWell: false,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The highlight: a small rounded square that just hugs the icon,
          // rather than a wide pill.
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: selected ? scheme.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconTheme.merge(
              data: IconThemeData(size: 22, color: fg),
              child: selected ? (destination.selectedIcon ?? destination.icon) : destination.icon,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            destination.label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
