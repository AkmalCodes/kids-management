import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// The app's own icon set, drawn in Figma to match the brand (rounded 2px
// strokes on a 24px grid). Source: Figma "KawanKecil — Brand & Icons", page
// "KawanKecil Brand v2", frame "Icons v2 · nav set", components
// `icon/<name>/outline` and `icon/<name>/filled`.
//
// Each value maps to two files: assets/icons/<name>_outline.svg and
// <name>_filled.svg. The enum value's `.name` IS the file prefix, so a new
// icon = new enum value + two exported SVGs with matching names.
enum AppIcons { people, schedule, lessons, attendance, reports, profile }

// Drop-in replacement for `Icon(Icons.xyz)` that draws one of [AppIcons].
//
// Like Icon, it reads size and colour from the nearest IconTheme when not
// given explicitly. That's what lets AppBottomNav tint it (dark rose when
// selected, muted otherwise) without knowing it isn't a regular Icon.
//
// The SVGs are single-colour (#5A2A33). ColorFilter with BlendMode.srcIn
// keeps each pixel's transparency but replaces its colour, so any tint
// works. The filled versions have real holes (the heart, the tick, the
// lines), not white shapes, so the tint can't fill them in.
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.filled = false,
    this.size,
    this.color,
  });

  final AppIcons icon;
  // Outline for unselected/normal use, filled for the selected state.
  final bool filled;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    final c = color ?? theme.color ?? const Color(0xFF000000);
    return SvgPicture.asset(
      'assets/icons/${icon.name}_${filled ? 'filled' : 'outline'}.svg',
      width: s,
      height: s,
      colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
    );
  }
}
