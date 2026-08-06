import 'package:flutter/material.dart';

// A "floating" bottom navigation bar: inset from the screen edges with
// rounded corners and a soft shadow, so it reads as a hovering pill.
//
// It takes the same NavigationDestination list as Material's NavigationBar,
// but renders the items itself. The reason: NavigationBar's selection
// indicator is a fixed 64x32 pill (hardcoded, not themeable) that looks too
// wide here, and it just cross-fades rather than sliding. Here the highlight
// is a small rounded square that **slides** horizontally from the old tab to
// the newly selected one.
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

  static const _barHeight = 60.0;
  // Gaps between the highlight and the bar edges (top/bottom + each side of
  // the slot) so it reads as a pill floating inside the bar.
  static const _vMargin = 8.0;
  static const _hMargin = 6.0;

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
                height: _barHeight,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final n = destinations.length;
                    final slot = constraints.maxWidth / n;
                    // The highlight wraps a whole item (icon + label), inset
                    // from the slot's sides and the bar's top/bottom.
                    // AnimatedPositioned tweens `left` when the parent rebuilds
                    // with a new selectedIndex -> the slide.
                    final left = selectedIndex * slot + _hMargin;
                    return Stack(
                      children: [
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                          top: _vMargin,
                          left: left,
                          width: slot - _hMargin * 2,
                          height: _barHeight - _vMargin * 2,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                        Row(
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
                      ],
                    );
                  },
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
    // The icon/label sit ON TOP of the sliding highlight (drawn behind in the
    // Stack), so items themselves have no background. Colour fades as the
    // highlight arrives.
    final fg = selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: IconTheme.merge(
              key: ValueKey(selected),
              data: IconThemeData(size: 20, color: fg),
              child: selected ? (destination.selectedIcon ?? destination.icon) : destination.icon,
            ),
          ),
          const SizedBox(height: 2),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
            child: Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
