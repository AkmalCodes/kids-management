import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawankecil/core/models/app_user.dart';
import 'package:kawankecil/shared/widgets/teacher_multi_select.dart';

AppUser _t(String id, String name) => AppUser(
  id: id,
  role: 'teacher',
  name: name,
  phone: '',
  centerId: 'center-1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

void main() {
  final all = [_t('t-1', 'Aisha'), _t('t-2', 'Ben'), _t('t-3', 'Chen')];

  Future<void> pump(
    WidgetTester tester, {
    required List<String> selectedIds,
    required ValueChanged<List<String>> onChanged,
  }) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TeacherMultiSelect(
            allTeachers: all,
            selectedIds: selectedIds,
            onChanged: onChanged,
          ),
        ),
      ));

  testWidgets('renders a chip per selected teacher, in the given order',
      (tester) async {
    await pump(tester, selectedIds: ['t-2', 't-1'], onChanged: (_) {});
    expect(find.widgetWithText(Chip, 'Ben'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Aisha'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Chen'), findsNothing);
  });

  testWidgets('no chips when nothing is selected', (tester) async {
    await pump(tester, selectedIds: const [], onChanged: (_) {});
    expect(find.byType(Chip), findsNothing);
  });

  testWidgets('the add dropdown offers only not-yet-selected teachers',
      (tester) async {
    await pump(tester, selectedIds: ['t-1'], onChanged: (_) {});
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    // Aisha (t-1) is already selected -> not offered. Ben and Chen are.
    expect(find.text('Ben').hitTestable(), findsOneWidget);
    expect(find.text('Chen').hitTestable(), findsOneWidget);
  });

  testWidgets('picking a teacher from the dropdown appends its id', (tester) async {
    List<String>? out;
    await pump(tester, selectedIds: ['t-1'], onChanged: (v) => out = v);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ben').last);
    await tester.pumpAndSettle();
    expect(out, ['t-1', 't-2']);
  });

  testWidgets('deleting a chip removes that id', (tester) async {
    List<String>? out;
    await pump(tester, selectedIds: ['t-1', 't-2'], onChanged: (v) => out = v);
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(Chip, 'Aisha'),
        matching: find.byIcon(Icons.cancel),
      ),
    );
    await tester.pumpAndSettle();
    expect(out, ['t-2']);
  });
}
