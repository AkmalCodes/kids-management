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
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _key, child: widget.build(context, _width));
}

// A DropdownButtonFormField replacement whose popup menu is exactly the
// width of the input field. DropdownButtonFormField gives its menu no
// explicit width, so Flutter sizes it to the button box (plus a start/end
// margin) and it overhangs the field. A plain DropdownButton accepts
// `menuWidth`; we feed it the field's own width from FieldWidthDropdown.
class AppDropdownField<T> extends StatefulWidget {
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
  State<AppDropdownField<T>> createState() => _AppDropdownFieldState<T>();
}

class _AppDropdownFieldState<T> extends State<AppDropdownField<T>> {
  // Holds the inner FormField's state so didUpdateWidget can re-sync it.
  final _fieldKey = GlobalKey<FormFieldState<T>>();

  @override
  void didUpdateWidget(AppDropdownField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // FormFieldState reads `initialValue` once and never again, so a parent
    // that rebuilds us with a different `value` (common when `value` is derived
    // from an async list that resolves after the first build) would be ignored.
    // DropdownButtonFormField's own state class re-syncs this the same way.
    // The `!= currentValue` guard stops this from fighting the user's own pick,
    // which already flowed back through field.didChange.
    if (widget.value != oldWidget.value &&
        _fieldKey.currentState?.value != widget.value) {
      _fieldKey.currentState?.didChange(widget.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormField<T>(
      key: _fieldKey,
      initialValue: widget.value,
      validator: widget.validator,
      builder: (field) {
        final effective = (widget.decoration ?? const InputDecoration())
            .applyDefaults(Theme.of(context).inputDecorationTheme)
            .copyWith(errorText: field.errorText);
        return InputDecorator(
          decoration: effective,
          // "Is there a selected item to show?" -- matches how
          // DropdownButtonFormField computes isEmpty. Several call sites use a
          // real DropdownMenuItem(value: null, child: Text('Unassigned')) and
          // default to null; that IS a selected item, so the label must float.
          isEmpty: !widget.items.any((item) => item.value == field.value),
          child: FieldWidthDropdown<T>(
            build: (context, menuWidth) => DropdownButton<T>(
              isExpanded: true,
              menuWidth: menuWidth,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              value: field.value,
              items: widget.items,
              onChanged: (v) {
                field.didChange(v);
                widget.onChanged(v);
              },
              // The InputDecorator draws the box; hide the button's own line.
              underline: const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }
}
