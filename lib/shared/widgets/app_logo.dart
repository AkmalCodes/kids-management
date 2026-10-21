import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// The brand mark ("Kids house", the P1 logo): a house roof sheltering a
// teacher with a heart on their chest, and a boy and girl cheek-to-cheek in
// front. Transparent background, so it sits on any screen colour.
//
// It's an SVG, not a PNG, so it stays sharp at any size. One file serves
// every screen density, unlike the launcher icon, which needs a PNG per
// density. Source of truth is the Figma file "KawanKecil — Brand &
// Icons", page "KawanKecil Brand v2", component "M1 · Mark / Kids house".
// If the logo changes there, re-export it as SVG over
// assets/logo/app_logo.svg.
//
// The art is 200x176, not square. SvgPicture's default BoxFit.contain fits
// it inside the size x size box without stretching.
//
// Colours are baked into the SVG (they're the AppTheme brand colours), so
// this deliberately doesn't take a `color` — tinting would flatten the
// multi-colour mark into a single-colour blob.
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
