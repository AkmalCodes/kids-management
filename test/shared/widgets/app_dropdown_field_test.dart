import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawankecil/shared/widgets/app_dropdown_field.dart';

Future<void> _pump(
  WidgetTester tester, {
  String? value,
  ValueChanged<String?>? onChanged,
  String? Function(String?)? validator,
  double width = 300,
}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: AppDropdownField<String>(
              value: value,
              onChanged: onChanged ?? (_) {},
              validator: validator,
              decoration: const InputDecoration(labelText: 'Pick'),
              items: const [
                DropdownMenuItem(value: 'a', child: Text('Apple')),
                DropdownMenuItem(value: 'b', child: Text('Banana')),
              ],
            ),
          ),
        ),
      ),
    ));

void main() {
  testWidgets('renders the selected item and the label', (tester) async {
    await _pump(tester, value: 'a');
    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('Pick'), findsOneWidget);
  });

  testWidgets('opening and picking fires onChanged and updates the shown value',
      (tester) async {
    String? picked;
    await _pump(tester, value: 'a', onChanged: (v) => picked = v);
    await tester.tap(find.text('Apple'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Banana').last);
    await tester.pumpAndSettle();
    expect(picked, 'b');
    expect(find.text('Banana'), findsOneWidget);
  });

  testWidgets(
      'the open popup menu matches the field width and left edge exactly '
      '(the actual bug: popup used to land short of the chevron)',
      (tester) async {
    await _pump(tester, value: 'a', width: 280);
    final fieldBox = tester.getRect(find.byType(InputDecorator));
    await tester.tap(find.text('Apple'));
    await tester.pumpAndSettle();
    // The menu's ListView is laid out by Flutter's own dropdown route to
    // exactly `menuWidth ?? buttonRect.width` at `buttonRect.left` -- with
    // ButtonTheme.alignedDropdown: true and DropdownButtonFormField's button
    // box being the whole field (chevron included), both should match the
    // field exactly, not land short on the right the way the unaligned
    // 16px/24px default margin used to.
    final menuBox = tester.getRect(find.byType(ListView));
    expect(menuBox.width, closeTo(fieldBox.width, 0.5));
    expect(menuBox.left, closeTo(fieldBox.left, 0.5));
  });

  testWidgets(
      'with a null option selected, the floating label is in the floating position',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: AppDropdownField<String>(
              value: null,
              onChanged: (_) {},
              decoration: const InputDecoration(labelText: 'Pick'),
              items: const [
                DropdownMenuItem(value: null, child: Text('Unassigned')),
                DropdownMenuItem(value: 'a', child: Text('Apple')),
              ],
            ),
          ),
        ),
      ),
    ));
    // The 'Unassigned' null option is a real, selected item, so the field is
    // NOT empty and the label floats above instead of sitting under the text.
    final decorator = tester.widget<InputDecorator>(find.byType(InputDecorator));
    expect(decorator.isEmpty, isFalse);
    expect(find.text('Pick'), findsOneWidget);
    expect(find.text('Unassigned'), findsOneWidget);
  });

  testWidgets('follows an externally changed value prop', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _ExternalValueHost()));
    // First build: the 'a' item is shown, 'b' is not.
    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('Banana'), findsNothing);
    // Parent rebuilds AppDropdownField with value flipped 'a' -> 'b'.
    await tester.tap(find.text('Flip'));
    await tester.pump();
    expect(find.text('Banana'), findsOneWidget);
  });

  testWidgets('validator error surfaces through the field', (tester) async {
    final formKey = GlobalKey<FormState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Form(
          key: formKey,
          child: AppDropdownField<String>(
            value: null,
            onChanged: (_) {},
            validator: (v) => v == null ? 'Required' : null,
            items: const [DropdownMenuItem(value: 'a', child: Text('Apple'))],
          ),
        ),
      ),
    ));
    formKey.currentState!.validate();
    await tester.pump();
    expect(find.text('Required'), findsOneWidget);
  });
}

// Test host that flips the `value` it passes to AppDropdownField, to prove an
// external value change is picked up (FormFieldState ignores initialValue after
// first build; AppDropdownField re-syncs it in didUpdateWidget).
class _ExternalValueHost extends StatefulWidget {
  const _ExternalValueHost();

  @override
  State<_ExternalValueHost> createState() => _ExternalValueHostState();
}

class _ExternalValueHostState extends State<_ExternalValueHost> {
  String _value = 'a';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppDropdownField<String>(
                value: _value,
                onChanged: (v) => setState(() => _value = v ?? _value),
                decoration: const InputDecoration(labelText: 'Pick'),
                items: const [
                  DropdownMenuItem(value: 'a', child: Text('Apple')),
                  DropdownMenuItem(value: 'b', child: Text('Banana')),
                ],
              ),
              TextButton(
                onPressed: () => setState(() => _value = 'b'),
                child: const Text('Flip'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
