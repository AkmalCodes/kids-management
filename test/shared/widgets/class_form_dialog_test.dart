import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawankecil/core/models/app_user.dart';
import 'package:kawankecil/shared/widgets/class_form_dialog.dart';

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
  final teachers = [_t('t-1', 'Aisha'), _t('t-2', 'Ben')];

  // Pumps a host with one button that opens the dialog and stashes its
  // result (and whether it resolved) for the test to assert on.
  Future<void> openDialog(
    WidgetTester tester, {
    required void Function(ClassFormResult?) onResult,
    required void Function() onDone,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                final result = await showClassFormDialog(
                  context,
                  title: 'New class',
                  teachers: teachers,
                );
                onResult(result);
                onDone();
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  // Opens the "Add teacher" dropdown and taps the named menu entry.
  Future<void> pickTeacher(WidgetTester tester, String name) async {
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  testWidgets('name + two teachers + Save resolves with the picked ids in order',
      (tester) async {
    ClassFormResult? result;
    var done = false;
    await openDialog(tester, onResult: (r) => result = r, onDone: () => done = true);

    await tester.enterText(find.byType(TextFormField), 'Toddlers');
    await pickTeacher(tester, 'Aisha');
    await pickTeacher(tester, 'Ben');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(done, isTrue);
    expect(result!.name, 'Toddlers');
    expect(result!.teacherIds, ['t-1', 't-2']);
  });

  testWidgets('Save with no teacher resolves teacherIds: const []', (tester) async {
    ClassFormResult? result;
    var done = false;
    await openDialog(tester, onResult: (r) => result = r, onDone: () => done = true);

    await tester.enterText(find.byType(TextFormField), 'Toddlers');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(done, isTrue);
    expect(result!.name, 'Toddlers');
    expect(result!.teacherIds, const <String>[]);
  });

  testWidgets('Cancel resolves null', (tester) async {
    ClassFormResult? result;
    var done = false;
    await openDialog(tester, onResult: (r) => result = r, onDone: () => done = true);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(done, isTrue);
    expect(result, isNull);
  });

  testWidgets('empty name shows the validator error and does not pop', (tester) async {
    var done = false;
    await openDialog(tester, onResult: (_) {}, onDone: () => done = true);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a name'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget); // dialog still open
    expect(done, isFalse);
  });
}
