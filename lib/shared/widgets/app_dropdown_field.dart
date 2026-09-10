import 'package:flutter/material.dart';

// A StatefulWidget that measures its width via GlobalKey after the first frame
// and passes it to a builder. Used by AppDropdownField and TeacherMultiSelect
// to measure the field's width for DropdownButton.menuWidth.
//
// menuWidth is null on the first frame, then set to the measured width after
// layout. This is safe: DropdownButton accepts null menuWidth, and by the time
// the user taps to open the menu, the post-frame callback has set the real width.
//
// Why this widget exists: a vanilla LayoutBuilder throws "does not support
// returning intrinsic dimensions" whenever an ancestor measures its intrinsic
// size. AlertDialog does exactly that -- it wraps its content in an
// IntrinsicWidth -- so an AppDropdownField or DropdownButton placed inside a
// dialog would crash. GlobalKey avoids that entirely.
class _FieldWidthDropdown<T> extends StatefulWidget {
  const _FieldWidthDropdown({required this.build});

  // build(context, menuWidth) returns the DropdownButton; menuWidth is null
  // on the first frame, then the measured field width.
  final Widget Function(BuildContext, double?) build;

  @override
  State<_FieldWidthDropdown<T>> createState() => _FieldWidthDropdownState<T>();
}

class _FieldWidthDropdownState<T> extends State<_FieldWidthDropdown<T>> {
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
// `menuWidth`; we feed it the field's own width from _FieldWidthDropdown.
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
    return FormField<T>(
      initialValue: value,
      validator: validator,
      builder: (field) {
        final effective = (decoration ?? const InputDecoration())
            .applyDefaults(Theme.of(context).inputDecorationTheme)
            .copyWith(errorText: field.errorText);
        return InputDecorator(
          decoration: effective,
          isEmpty: field.value == null,
          child: _FieldWidthDropdown<T>(
            build: (context, menuWidth) => DropdownButton<T>(
              isExpanded: true,
              menuWidth: menuWidth,
              borderRadius: BorderRadius.circular(borderRadius),
              value: field.value,
              items: items,
              onChanged: (v) {
                field.didChange(v);
                onChanged(v);
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
