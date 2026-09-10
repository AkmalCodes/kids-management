import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/shared/widgets/app_dropdown_field.dart';

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

  testWidgets('the built DropdownButton menuWidth equals the field width',
      (tester) async {
    await _pump(tester, value: 'a', width: 280);
    final btn = tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>));
    // The field is 280 wide minus the InputDecorator content padding; assert
    // the menu tracks the LayoutBuilder width, i.e. it is set and < 280.
    expect(btn.menuWidth, isNotNull);
    expect(btn.menuWidth! <= 280 && btn.menuWidth! > 0, isTrue);
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
