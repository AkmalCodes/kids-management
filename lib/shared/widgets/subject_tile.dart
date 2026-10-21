import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'app_icon.dart';

// The small rounded square at the start of a lesson plan card, giving each
// subject a recognisable look (screen design A, Figma page "Screen designs").
//
// Subjects are free-text rows the director creates ("Arts", "Motor
// skills"...), so we can't ship a hand-drawn icon per subject. Instead the
// tile shows the subject's initials on a pastel colour picked from the name.
// The same name always gets the same colour, on every screen and every
// launch. No subject = a neutral book icon.
class SubjectTile extends StatelessWidget {
  const SubjectTile({super.key, this.name, this.size = 44});

  final String? name;
  final double size;

  // (background, text) pairs: soft enough to sit beside the brand pink, dark
  // enough text to stay readable.
  static const _palette = [
    (Color(0xFFFFE4EC), Color(0xFFC2507A)), // pink
    (Color(0xFFFFEBDD), Color(0xFFB85C1F)), // peach
    (Color(0xFFF1E6F5), Color(0xFF7B4A8C)), // lilac
    (Color(0xFFE3F1F4), Color(0xFF2F6F7E)), // teal
    (Color(0xFFEAF3DD), Color(0xFF557A2E)), // sage
  ];

  // Stable hash of the name. Not String.hashCode: Dart doesn't promise that
  // stays the same between app runs, and the colour must never change.
  static int _paletteIndex(String name) {
    var h = 0;
    for (final c in name.toLowerCase().codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h % _palette.length;
  }

  // "Motor skills" -> "MS", "Arts" -> "Ar".
  static String initials(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '';
    if (words.length > 1) return (words[0][0] + words[1][0]).toUpperCase();
    final w = words.first;
    return w.length == 1 ? w.toUpperCase() : w[0].toUpperCase() + w[1].toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final n = name?.trim() ?? '';
    final radius = BorderRadius.circular(size * 0.32);
    if (n.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: AppTheme.barTint, borderRadius: radius),
        alignment: Alignment.center,
        child: AppIcon(AppIcons.lessons, size: size * 0.5, color: AppTheme.onAccent),
      );
    }
    final (background, foreground) = _palette[_paletteIndex(n)];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background, borderRadius: radius),
      alignment: Alignment.center,
      child: Text(
        initials(n),
        style: TextStyle(
          color: foreground,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
