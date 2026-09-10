import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Centralized so every screen picks up the same look automatically —
// change the seed color or radius here and it cascades everywhere,
// instead of hunting through each widget for hardcoded styling.
class AppTheme {
  AppTheme._();

  static const seed = Color(0xFFFDB0C0);      // soft pink — the accent colour
  static const onAccent = Color(0xFF5A2A33);  // dark rose — text/icons ON soft pink
  static const barTint = Color(0xFFFFF2F5);   // faint wash on the top/bottom bars
  static const radius = 16.0;

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(seedColor: seed).copyWith(
      surface: Colors.white,
      primary: seed,
      onPrimary: onAccent,
    );
    // Applies Nunito to every standard text style (buttons, app bar
    // titles, list tiles, etc. all resolve their font from this), so
    // switching the app's font is just this one line.
    final textTheme = GoogleFonts.nunitoTextTheme();

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.white,
      textTheme: textTheme,

      appBarTheme: AppBarTheme(
        backgroundColor: barTint,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
        // A slimmer top bar (default is 56) to give content more room.
        toolbarHeight: 48,
        // Rounded bottom edges so the top bar reads as a rounded panel.
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
      ),

      // Round each list row's ink/long-press highlight so it matches the
      // rounded cards/containers instead of a boxy full-width splash.
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: onAccent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onAccent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: onAccent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),

      // Filled, borderless fields read as more modern than boxed outlines —
      // the rounded fill itself communicates "this is tappable".
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),

      // Material 3's NavigationBar (pill-shaped selection indicator) reads
      // as more modern than the older BottomNavigationBar — used in every
      // shell instead.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: barTint,
        // The soft pink pill so the selected tab stands out clearly against
        // the faint bar.
        indicatorColor: seed,
        elevation: 0,
        // Slimmer than the 80 default; the AppBottomNav floats it off the
        // screen edges (see shared/widgets/app_bottom_nav.dart).
        height: 62,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        // A rounder selection pill so the highlight echoes the bar's own
        // rounded shape rather than a stadium that looks foreign.
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        // Bolder + smaller labels.
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: seed.withValues(alpha: 0.15),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
    );
  }
}
