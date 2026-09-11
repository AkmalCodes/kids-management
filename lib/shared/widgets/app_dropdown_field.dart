import 'package:flutter/material.dart';

// A StatefulWidget that measures its width via GlobalKey after the first frame
// and passes it to a builder. Used by AppDropdownField and TeacherMultiSelect
// to measure the field's width for DropdownButton.menuWidth.
//
// menuWidth is null on the first frame, then set to the measured width after
// layout. This is safe: DropdownButton accepts null menuWidth, and by the time
// the user taps to open the menu, the post-frame callback has set the real width.
//
// Width is measured exactly once, from a post-frame callback in initState. If
// this same State later re-lays-out at a different width (e.g. a parent resizes
// it), menuWidth stays stale -- there is no resize listener. Acceptable here
// because every user lives in a fixed-width AlertDialog or filter bar that
// doesn't change width for the life of the widget.
//
// Why this widget exists: a vanilla LayoutBuilder throws "does not support
// returning intrinsic dimensions" whenever an ancestor measures its intrinsic
// size. AlertDialog does exactly that -- it wraps its content in an
// IntrinsicWidth -- so an AppDropdownField or DropdownButton placed inside a
// dialog would crash. GlobalKey avoids that entirely.
class FieldWidthDropdown<T> extends StatefulWidget {
  const FieldWidthDropdown({super.key, required this.build});

  // build(context, menuWidth) returns the DropdownButton; menuWidth is null
  // on the first frame, then the measured field width.
  final Widget Function(BuildContext, double?) build;

  @override
  State<FieldWidthDropdown<T>> createState() => _FieldWidthDropdownState<T>();
}

class _FieldWidthDropdownState<T> extends State<FieldWidthDropdown<T>> {
  final _key = GlobalKey();
  double? _width;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final w = _key.currentContext?.size?.width;
      if (w != null && w != _width && mounted) setState(() => _width = w);
    });
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(
        key: _key,
        // alignedDropdown: true turns off DropdownButton's old built-in
        // popup margin (16px left / 24px right by default), which is what
        // made the popup's right edge land short of the box's own right
        // edge -- right where the dropdown's arrow icon sits. With this on,
        // the popup lines up exactly with the box we measured.
        child: ButtonTheme(
          alignedDropdown: true,
          child: widget.build(context, _width),
        ),
      );
}

// A thin DropdownButtonFormField wrapper that fixes the field-width bug at
// its actual source instead of re-measuring around it.
//
// Why not measure our own width (the FieldWidthDropdown approach above)?
// DropdownButtonFormField builds its DropdownButton *inside the same State*
// as its InputDecorator (Focus > GestureDetector > InputDecorator, all in one
// build() call) -- so when it measures its own render box to position and
// size the popup, that box IS the whole visible field, chevron included.
// Our own earlier attempt put InputDecorator *outside*, wrapping a plain
// DropdownButton as its child -- so the button's own box was only the
// content area *inside* InputDecorator's padding, permanently ~16px short on
// each side no matter what menuWidth we fed it. That was a nesting-order bug,
// not a margin bug -- no amount of manual measuring could have fixed it.
//
// The real, framework-native fix is ButtonTheme(alignedDropdown: true): it
// zeroes the popup's default 16px-start/24px-end margin (which exists so a
// plain, undecorated DropdownButton's menu doesn't touch the screen edges),
// so the popup anchors to *exactly* the button's own box. Since that box is
// already the full field for DropdownButtonFormField, the popup now matches
// the field exactly -- no GlobalKey, no post-frame callback, no menuWidth
// plumbing needed.
class AppDropdownField<T> extends StatelessWidget {
  const AppDropdownField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.decoration,
    this.validator,
    this.borderRadius = 16,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final InputDecoration? decoration;
  final String? Function(T?)? validator;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ButtonTheme(
      alignedDropdown: true,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        borderRadius: BorderRadius.circular(borderRadius),
        decoration: decoration ?? const InputDecoration(),
        items: items,
        onChanged: onChanged,
        validator: validator,
      ),
    );
  }
}
