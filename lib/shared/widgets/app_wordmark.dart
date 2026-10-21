import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// The "KawanKecil" name as drawn in the brand board: "Kawan" in accent pink,
// "Kecil" in dark rose, with a small heart dotting the "i".
//
// Why an SVG and not a Text widget: the lettering is Fredoka Bold, and the
// heart-dot can't be made with a font. Figma exported the letters as outlined
// paths, so the app doesn't need to bundle or download Fredoka at all.
// Source: Figma "KawanKecil Brand v2" page, component "W1 · Wordmark".
//
// Only [width] is taken: the height follows from the SVG's 479:116 aspect
// ratio, so the word can never be squashed.
class AppWordmark extends StatelessWidget {
  const AppWordmark({super.key, this.width = 220});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/logo/app_wordmark.svg',
      width: width,
      // Screen readers read this instead of trying to describe the paths.
      semanticsLabel: 'KawanKecil',
    );
  }
}
