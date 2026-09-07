import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/core/models/schedule.dart';
import 'package:kids_management/shared/widgets/schedule_entry_form_dialog.dart';

// A fixed anchor date threaded through every dialog: Wed 9 Sep 2026.
final _anchor = DateTime(2026, 9, 9);

ScheduleEntry _entry({String color = 'D81B60', String recurrence = 'weekly'}) => ScheduleEntry(
  id: 'entry-1',
  type: 'teacher',
  refId: 'teacher-1',
  centerId: 'center-1',
  day: 'Monday',
  startTime: '08:00',
  endTime: '09:00',
  label: 'Art',
  color: color,
  recurrence: recurrence,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'teacher-1',
  updatedBy: 'teacher-1',
);

// A button that opens the dialog and stashes the result, so tests can pump
// a real widget tree (showDialog needs a Navigator/MaterialApp context).
class _Harness extends StatefulWidget {
  _Harness({this.existing, DateTime? anchorDate}) : anchorDate = anchorDate ?? _anchor;
  final ScheduleEntry? existing;
  final DateTime anchorDate;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  ScheduleEntryFormResult? result;
  bool opened = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          ElevatedButton(
            onPressed: () async {
              final r = await showScheduleEntryFormDialog(
                context,
                existing: widget.existing,
                anchorDate: widget.anchorDate,
              );
              setState(() {
                result = r;
                opened = true;
              });
            },
            child: const Text('Open'),
          ),
          Text(!opened ? 'no result' : (result?.runtimeType.toString() ?? 'null result')),
          if (result is ScheduleEntrySaved) ...[
            Text((result as ScheduleEntrySaved).label),
            Text('color:${(result as ScheduleEntrySaved).color}'),
            Text('recurrence:${(result as ScheduleEntrySaved).recurrence}'),
            Text('anchor:${(result as ScheduleEntrySaved).anchorDate.toIso8601String()}'),
          ],
        ],
      ),
    );
  }
}

void main() {
  testWidgets('add mode shows no Delete button and default times', (tester) async {
    await tester.pumpWidget(MaterialApp(home: _Harness()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Create Event'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Start: 08:00'), findsOneWidget);
    expect(find.text('End: 09:00'), findsOneWidget);
  });

  testWidgets('edit mode pre-fills label, times, and shows Delete', (tester) async {
    await tester.pumpWidget(MaterialApp(home: _Harness(existing: _entry())));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Event'), findsOneWidget);
    expect(find.text('Art'), findsOneWidget);
    expect(find.text('Start: 08:00'), findsOneWidget);
    expect(find.text('End: 09:00'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('empty label blocks save', (tester) async {
    await tester.pumpWidget(MaterialApp(home: _Harness()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Please enter an event name'), findsOneWidget);
    expect(find.text('Create Event'), findsOneWidget); // dialog still open
  });

  testWidgets('save returns ScheduleEntrySaved with the entered label', (tester) async {
    await tester.pumpWidget(MaterialApp(home: _Harness()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Music');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('ScheduleEntrySaved'), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);
  });

  testWidgets('delete returns ScheduleEntryDeleted', (tester) async {
    await tester.pumpWidget(MaterialApp(home: _Harness(existing: _entry())));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('ScheduleEntryDeleted'), findsOneWidget);
  });

  testWidgets('cancel returns null', (tester) async {
    await tester.pumpWidget(MaterialApp(home: _Harness()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('null result'), findsOneWidget);
  });

  testWidgets('add mode defaults to the default palette color', (tester) async {
    await tester.pumpWidget(MaterialApp(home: _Harness()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Music');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('color:26A69A'), findsOneWidget);
  });

  testWidgets('edit mode pre-selects the entry\'s existing color', (tester) async {
    await tester.pumpWidget(MaterialApp(home: _Harness(existing: _entry(color: 'EF5350'))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('color:EF5350'), findsOneWidget);
  });

  testWidgets('tapping a different swatch changes the saved color', (tester) async {
    await tester.pumpWidget(MaterialApp(home: _Harness()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Music');
    await tester.tap(find.byKey(const Key('color-swatch-Magenta')));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('color:D81B60'), findsOneWidget);
  });

  testWidgets('add mode shows a Repeats field defaulting to Weekly', (tester) async {
    await tester.pumpWidget(MaterialApp(home: _Harness()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Repeats'), findsOneWidget);
    expect(find.text('Weekly'), findsOneWidget);
    // Helper text for a Wednesday anchor + weekly selection.
    expect(find.text('Repeats every Wednesday'), findsOneWidget);
  });

  testWidgets('edit mode seeds Repeats from the entry recurrence', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: _Harness(existing: _entry(recurrence: 'monthly'))),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Monthly'), findsOneWidget);
    expect(
      find.text('Repeats on day 9 each month (the last day in shorter months)'),
      findsOneWidget,
    );
  });

  testWidgets('helper text switches from weekly to monthly when the dropdown changes',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: _Harness()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Repeats every Wednesday'), findsOneWidget);

    await tester.tap(find.text('Weekly'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monthly').last);
    await tester.pumpAndSettle();

    expect(find.text('Repeats every Wednesday'), findsNothing);
    expect(
      find.text('Repeats on day 9 each month (the last day in shorter months)'),
      findsOneWidget,
    );
  });

  testWidgets('selecting Monthly then Save returns recurrence and anchorDate', (tester) async {
    await tester.pumpWidget(MaterialApp(home: _Harness()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Music');
    await tester.tap(find.text('Weekly'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monthly').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('recurrence:monthly'), findsOneWidget);
    expect(find.text('anchor:${DateTime(2026, 9, 9).toIso8601String()}'), findsOneWidget);
  });

  testWidgets('untouched dialog returns recurrence weekly', (tester) async {
    await tester.pumpWidget(MaterialApp(home: _Harness()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Music');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('recurrence:weekly'), findsOneWidget);
  });
}
