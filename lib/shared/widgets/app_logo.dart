import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// The brand mark (logo D1, "Family in the blocks"): three toy blocks holding
// a grown-up + child, a book and a heart, on a rounded wash tile.
//
// It's an SVG, not a PNG, so it stays sharp at any size. One file serves
// every screen density, unlike the launcher icon, which needs a PNG per
// density. Source of truth is the Figma file "KawanKecil — Brand &
// Icons" (frame "Logo D1 — Family in the blocks / mark"). If the logo
// changes there, re-export it as SVG over assets/logo/app_logo.svg.
//
// Colours are baked into the SVG (they're the AppTheme brand colours), so
// this deliberately doesn't take a `color` — tinting would flatten the
// three-colour mark into a single-colour blob.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/logo/app_logo.svg',
      width: size,
      height: size,
      // Read aloud by TalkBack/VoiceOver, since the logo has no visible text.
      semanticsLabel: 'KawanKecil logo',
    );
  }
}
