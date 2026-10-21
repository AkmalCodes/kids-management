import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

// A "floating" bottom navigation bar: inset from the screen edges with
// rounded corners and a soft shadow, so it reads as a hovering pill.
//
// It takes the same NavigationDestination list as Material's NavigationBar,
// but renders the items itself. NavigationBar's selection indicator is a
// fixed 64x32 pill (hardcoded, not themeable) and it can't do this layout:
//
//   unselected tabs show only their icon;
//   the selected tab shows [icon][label] on one line.
//
// When a tab is picked, three things animate together, with the same
// duration and curve so they stay in step:
//   1. the slots resize: the new tab grows to fit its label, the old one
//      shrinks back to icon-only (AnimatedContainer widths);
//   2. the highlight pill slides to the new tab and stretches to its new
//      width (AnimatedPositioned left + width);
//   3. the label slides out to the right from behind the icon, while the
//      old tab's label slides back in (_NavItem's reveal animation).
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
  static const _vMargin = 6.0;
  static const _hMargin = 4.0;

  // Shared by every animated piece so they move as one.
  static const _duration = Duration(milliseconds: 280);
  static const _curve = Curves.easeOutCubic;

  // Item geometry, used both to draw the items and to work out how wide the
  // selected slot must be: padding + icon + gap + label + padding.
  static const _iconSize = 20.0;
  static const _gap = 6.0; // between the icon and its label
  static const _itemPad = 14.0; // inside the highlight, each side
  // Narrowest an icon-only tab may get, so it stays easy to tap.
  static const _minSlot = 48.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        // Small gap on all sides so the bar hovers off the edges.
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
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
              color: AppTheme.barTint,
              child: SizedBox(
                height: _barHeight,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // One style for measuring AND drawing the labels, so the
                    // measured width matches what's painted. Merging onto
                    // DefaultTextStyle keeps the app font (Nunito).
                    final labelStyle = DefaultTextStyle.of(context).style.merge(
                          const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        );
                    // Respect the phone's font-size setting when measuring.
                    final textScaler = MediaQuery.textScalerOf(context);

                    final n = destinations.length;
                    final total = constraints.maxWidth;
                    // Room left for a label once the other tabs keep their
                    // minimum width. Longer labels get an ellipsis.
                    final maxLabel = (total -
                            (n - 1) * _minSlot -
                            _itemPad * 2 -
                            _iconSize -
                            _gap)
                        .clamp(0.0, double.infinity);
                    final labelWidths = [
                      for (final d in destinations)
                        _measure(d.label, labelStyle, textScaler)
                            .clamp(0.0, maxLabel),
                    ];

                    // Selected slot = exactly what [icon][label] needs, but
                    // never narrower than an even share of the bar. The
                    // other tabs split whatever is left equally.
                    final selectedWidth = (_itemPad * 2 +
                            _iconSize +
                            _gap +
                            labelWidths[selectedIndex])
                        .clamp(total / n, total);
                    final otherWidth =
                        n > 1 ? (total - selectedWidth) / (n - 1) : 0.0;
                    // Selected slot's left edge = the slots before it, which
                    // are all unselected, so all `otherWidth` wide.
                    final left = otherWidth * selectedIndex;

                    return Stack(
                      children: [
                        AnimatedPositioned(
                          duration: _duration,
                          curve: _curve,
                          top: _vMargin,
                          left: left + _hMargin,
                          width: selectedWidth - _hMargin * 2,
                          height: _barHeight - _vMargin * 2,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            for (var i = 0; i < n; i++)
                              AnimatedContainer(
                                duration: _duration,
                                curve: _curve,
                                width: i == selectedIndex
                                    ? selectedWidth
                                    : otherWidth,
                                child: _NavItem(
                                  destination: destinations[i],
                                  selected: i == selectedIndex,
                                  scheme: scheme,
                                  labelStyle: labelStyle,
                                  labelWidth: labelWidths[i],
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

  // Width a label will take when painted on one line. TextPainter is the
  // same text engine a Text widget uses, run here without drawing anything.
  static double _measure(String text, TextStyle style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    // Round up: a fraction of a pixel short would trigger the ellipsis.
    return width.ceilToDouble();
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.scheme,
    required this.labelStyle,
    required this.labelWidth,
    required this.onTap,
  });

  final NavigationDestination destination;
  final bool selected;
  final ColorScheme scheme;
  final TextStyle labelStyle;
  final double labelWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The icon/label sit ON TOP of the sliding highlight (drawn behind in the
    // Stack), so items themselves have no background. Colour fades as the
    // highlight arrives.
    final fg = selected ? AppTheme.onAccent : scheme.onSurfaceVariant;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        // `reveal` runs 0 -> 1 when this tab gets selected, 1 -> 0 when it
        // loses selection. TweenAnimationBuilder starts at `end` on the
        // first build, so nothing animates when the screen first opens.
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: selected ? 1 : 0),
          duration: AppBottomNav._duration,
          curve: AppBottomNav._curve,
          // The icon doesn't depend on `reveal`, so it's built once and
          // handed to the builder as `child` instead of rebuilt every frame.
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: IconTheme.merge(
              key: ValueKey(selected),
              data: IconThemeData(size: AppBottomNav._iconSize, color: fg),
              child: selected
                  ? (destination.selectedIcon ?? destination.icon)
                  : destination.icon,
            ),
          ),
          builder: (context, reveal, icon) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon!,
              // Flexible: if a resize is interrupted halfway (rapid taps),
              // the label squeezes (ellipsis) instead of overflowing.
              Flexible(
                // ClipRect hides whatever part of the label is outside its
                // box. The box starts at the icon's right edge, so the text
                // looks like it's coming out from behind the icon.
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    // Box width = reveal x label width: 0 when unselected,
                    // so an icon-only tab takes no extra room.
                    widthFactor: reveal,
                    child: Transform.translate(
                      // Text starts one full label-width to the left (tucked
                      // under the icon) and glides right into place.
                      offset: Offset(
                        -(1 - reveal) * (labelWidth + AppBottomNav._gap),
                        0,
                      ),
                      child: Padding(
                        padding:
                            const EdgeInsets.only(left: AppBottomNav._gap),
                        child: SizedBox(
                          width: labelWidth,
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: labelStyle.copyWith(color: fg),
                            child: Text(
                              destination.label,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
