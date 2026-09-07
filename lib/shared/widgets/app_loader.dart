import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

// Themed drop-in replacement for CircularProgressIndicator, used at every
// loading state across the app (page loads, section loads, button spinners)
// instead of Material's default gray spinner.
//
// Two things it adds over a bare CircularProgressIndicator:
//  - Color: uses the app's seed pink (colorScheme.primary) instead of the
//    default adaptive gray, so it actually matches the theme.
//  - Debounce (delayed: true, the default): stays invisible for the first
//    250ms after mounting, then pops in with a fade+scale. A load that
//    finishes inside 250ms never shows anything at all -- no flash for fast
//    screens. Only genuinely slow loads (like the login -> dashboard gap)
//    get the loader, and it arrives as an intentional pop-in rather than an
//    abrupt appear.
// Pass delayed: false for button-press spinners, where the user just
// tapped and expects instant feedback rather than a 250ms dead zone.
class AppLoader extends StatefulWidget {
  const AppLoader({super.key, this.size = 36, this.delayed = true});

  final double size;
  final bool delayed;

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader> {
  static const _debounce = Duration(milliseconds: 250);
  static const _entrance = Duration(milliseconds: 200);

  // Starts hidden when delayed, visible immediately otherwise.
  late bool _visible = !widget.delayed;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    if (widget.delayed) {
      _debounceTimer = Timer(_debounce, () => setState(() => _visible = true));
    }
  }

  @override
  void dispose() {
    // Without this, a load that resolves (and unmounts this widget) before
    // the debounce fires leaves the Timer running -- harmless in the app,
    // but flutter_test's leaked-timer check fails any test whose teardown
    // races ahead of it.
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.onAccent;

    return AnimatedOpacity(
      opacity: _visible ? 1.0 : 0.0,
      duration: _entrance,
      child: AnimatedScale(
        scale: _visible ? 1.0 : 0.8,
        duration: _entrance,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: CircularProgressIndicator(
            strokeWidth: widget.size / 18,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ),
    );
  }
}
