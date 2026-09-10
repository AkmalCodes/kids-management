import 'package:flutter/material.dart';

// A DropdownButtonFormField replacement whose popup menu is exactly the
// width of the input field. DropdownButtonFormField gives its menu no
// explicit width, so Flutter sizes it to the button box and it overhangs
// the field. A plain DropdownButton accepts `menuWidth`; we feed it the
// field's own width from a LayoutBuilder.
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
          child: LayoutBuilder(
            builder: (context, constraints) => DropdownButton<T>(
              isExpanded: true,
              menuWidth: constraints.maxWidth,
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
