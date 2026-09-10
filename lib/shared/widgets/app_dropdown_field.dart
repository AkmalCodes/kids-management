import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

// A DropdownButtonFormField replacement whose popup menu is exactly the
// width of the input field. DropdownButtonFormField gives its menu no
// explicit width, so Flutter sizes it to the button box (plus a start/end
// margin) and it overhangs the field. A plain DropdownButton accepts
// `menuWidth`; we feed it the field's own width from a MenuWidthBuilder.
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
          child: MenuWidthBuilder(
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

// A LayoutBuilder that also answers intrinsic-dimension queries instead of
// throwing on them.
//
// Why this exists: the vanilla LayoutBuilder throws
// "LayoutBuilder does not support returning intrinsic dimensions" whenever an
// ancestor measures its intrinsic size. AlertDialog does exactly that -- it
// wraps its content in an IntrinsicWidth -- so an AppDropdownField (or the
// teacher-picker DropdownButton, which uses this too) placed inside a dialog
// would crash the whole subtree.
//
// It is safe to answer those queries here: the builder is only used to pass
// the field's width to DropdownButton.menuWidth, which sizes the *popup
// overlay*, never the button box. So the child's intrinsic size does not
// depend on the constraints the builder is called with, and delegating the
// query straight to the child gives the right answer.
class MenuWidthBuilder extends ConstrainedLayoutBuilder<BoxConstraints> {
  const MenuWidthBuilder({super.key, required super.builder});

  @override
  RenderAbstractLayoutBuilderMixin<BoxConstraints, RenderBox> createRenderObject(
    BuildContext context,
  ) => _RenderMenuWidthBuilder();
}

class _RenderMenuWidthBuilder extends RenderBox
    with
        RenderObjectWithChildMixin<RenderBox>,
        RenderObjectWithLayoutCallbackMixin,
        RenderAbstractLayoutBuilderMixin<BoxConstraints, RenderBox> {
  // The only deviation from Flutter's private _RenderLayoutBuilder: these four
  // delegate to the child rather than throwing. See MenuWidthBuilder's note.
  @override
  double computeMinIntrinsicWidth(double height) =>
      child?.getMinIntrinsicWidth(height) ?? 0.0;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      child?.getMaxIntrinsicWidth(height) ?? 0.0;

  @override
  double computeMinIntrinsicHeight(double width) =>
      child?.getMinIntrinsicHeight(width) ?? 0.0;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      child?.getMaxIntrinsicHeight(width) ?? 0.0;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    assert(
      debugCannotComputeDryLayout(
        reason: 'Calculating the dry layout would require running the layout '
            'callback speculatively, which might mutate the live render object tree.',
      ),
    );
    return Size.zero;
  }

  @override
  void performLayout() {
    final BoxConstraints constraints = this.constraints;
    runLayoutCallback();
    if (child != null) {
      child!.layout(constraints, parentUsesSize: true);
      size = constraints.constrain(child!.size);
    } else {
      size = constraints.biggest;
    }
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    return child?.getDistanceToActualBaseline(baseline) ??
        super.computeDistanceToActualBaseline(baseline);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return child?.hitTest(result, position: position) ?? false;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final RenderBox? child = this.child;
    if (child != null) {
      context.paintChild(child, offset);
    }
  }
}
