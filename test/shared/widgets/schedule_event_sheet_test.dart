import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawankecil/core/models/schedule.dart';
import 'package:kawankecil/shared/widgets/schedule_event_sheet.dart';

// Wednesday 9 Sep 2026: the day being viewed in these tests.
final _wed = DateTime(2026, 9, 9);

ScheduleEntry _entry({
  String label = 'Art',
  String day = 'Monday',
  String color = 'EF5350',
  String recurrence = 'weekly',
  DateTime? anchorDate,
  String? lessonPlanId,
}) =>
    ScheduleEntry(
      id: 'e1',
      type: 'class',
      refId: 'class-1',
      centerId: 'center-1',
      day: day,
      startTime: '08:00',
      endTime: '09:00',
      label: label,
      color: color,
      recurrence: recurrence,
      anchorDate: anchorDate,
      lessonPlanId: lessonPlanId,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      createdBy: 'teacher-1',
      updatedBy: 'teacher-1',
    );

// A button that opens the sheet, then prints what it returned so tests can
// assert on it.
class _Harness extends StatefulWidget {
  const _Harness(this.open);
  final Future<ScheduleSheetResult?> Function(BuildContext) open;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  String _out = 'none';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          ElevatedButton(
            onPressed: () async {
              final r = await widget.open(context);
              setState(() {
                _out = switch (r) {
                  null => 'null result',
                  ScheduleEntrySaved() =>
                    'saved:${r.label}|${r.startTime}-${r.endTime}|color:${r.color}|'
                        'recurrence:${r.recurrence}|anchor:${r.anchorDate.toIso8601String()}|'
                        'plan:${r.lessonPlanId}',
                  ScheduleEntryDeleted() => 'deleted',
                  ScheduleOpenPlan() => 'open plan',
                };
              });
            },
            child: const Text('open'),
          ),
          Text(_out, key: const Key('out')),
        ],
      ),
    );
  }
}

Future<void> _open(
  WidgetTester tester,
  Future<ScheduleSheetResult?> Function(BuildContext) open,
) async {
  await tester.pumpWidget(MaterialApp(home: _Harness(open)));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

String _out(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('out'))).data!;

void main() {
  group('create mode', () {
    Future<void> openCreate(WidgetTester tester,
            {String? start, String? end, List<LessonPlanOption> plans = const []}) =>
        _open(
          tester,
          (c) => showScheduleEventSheet(c,
              date: _wed,
              canEdit: true,
              initialStartTime: start,
              initialEndTime: end,
              lessonPlans: plans),
        );

    testWidgets('opens straight into the form with default times', (tester) async {
      await openCreate(tester);
      expect(find.text('New event'), findsOneWidget);
      expect(find.text('08:00'), findsOneWidget);
      expect(find.text('09:00'), findsOneWidget);
      expect(find.text('Add event'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('an empty name blocks saving', (tester) async {
      await openCreate(tester);
      await tester.tap(find.text('Add event'));
      await tester.pumpAndSettle();
      expect(find.text('Please enter an event name'), findsOneWidget);
      expect(find.text('New event'), findsOneWidget); // still open
    });

    testWidgets('an end before the start blocks saving', (tester) async {
      await openCreate(tester, start: '10:00', end: '09:00');
      await tester.enterText(find.byKey(const Key('event-name')), 'Music');
      await tester.tap(find.text('Add event'));
      await tester.pumpAndSettle();
      expect(find.text('End time must be after the start time'), findsOneWidget);
      expect(_out(tester), 'none');
    });

    testWidgets('saving returns the entered values; untouched = weekly, default colour, viewed date',
        (tester) async {
      await openCreate(tester, start: '10:00', end: '11:00');
      await tester.enterText(find.byKey(const Key('event-name')), 'Music');
      await tester.tap(find.text('Add event'));
      await tester.pumpAndSettle();
      expect(
        _out(tester),
        'saved:Music|10:00-11:00|color:26A69A|recurrence:weekly|'
        'anchor:${_wed.toIso8601String()}|plan:null',
      );
    });

    testWidgets('tapping a swatch changes the saved colour', (tester) async {
      await openCreate(tester);
      await tester.enterText(find.byKey(const Key('event-name')), 'Music');
      await tester.tap(find.byKey(const Key('color-swatch-Magenta')));
      await tester.tap(find.text('Add event'));
      await tester.pumpAndSettle();
      expect(_out(tester), contains('color:D81B60'));
    });

    testWidgets('the repeat picker spells out the rule and is returned', (tester) async {
      await openCreate(tester);
      expect(find.text('Repeats every Wednesday'), findsOneWidget);

      await tester.tap(find.byKey(const Key('repeat-daily')));
      await tester.pumpAndSettle();
      expect(find.text('Repeats every weekday'), findsOneWidget);

      await tester.tap(find.byKey(const Key('repeat-once')));
      await tester.pumpAndSettle();
      expect(find.text('Occurs once on 9 Sep 2026'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('event-name')), 'Trip');
      await tester.tap(find.text('Add event'));
      await tester.pumpAndSettle();
      expect(_out(tester), contains('recurrence:once'));
      expect(_out(tester), contains('anchor:${_wed.toIso8601String()}'));
    });

    testWidgets('the lesson plan picker only shows when plans are offered', (tester) async {
      await openCreate(tester);
      expect(find.text('Lesson plan'), findsNothing);
    });

    testWidgets('with plans offered, the picked plan is returned', (tester) async {
      await openCreate(tester, plans: [(id: 'lp-1', label: 'Watercolours · Art')]);
      expect(find.text('Lesson plan'), findsOneWidget);
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Watercolours · Art').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('event-name')), 'Painting');
      await tester.tap(find.text('Add event'));
      await tester.pumpAndSettle();
      expect(_out(tester), contains('plan:lp-1'));
    });

    testWidgets('Cancel closes the sheet', (tester) async {
      await openCreate(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(_out(tester), 'null result');
    });

    testWidgets('fits a short viewport (keyboard up) without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await openCreate(tester, plans: [(id: 'lp-1', label: 'Watercolours · Art')]);
      expect(tester.takeException(), isNull);
    });
  });

  group('view mode', () {
    testWidgets('summary: time, length, repeat rule and actions for an editor', (tester) async {
      await _open(tester,
          (c) => showScheduleEventSheet(c, entry: _entry(), date: _wed, canEdit: true, addedByYou: true));
      expect(find.text('Art'), findsOneWidget);
      expect(find.text('08:00 – 09:00'), findsOneWidget);
      expect(find.text('Wednesday, 9 Sep · 1 hr'), findsOneWidget);
      expect(find.text('Every Monday'), findsOneWidget);
      expect(find.text('Added by you'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('read-only: no actions, the hint explains why', (tester) async {
      await _open(
          tester,
          (c) => showScheduleEventSheet(c,
              entry: _entry(), date: _wed, readOnlyHint: 'Only the creator or a director can edit this event.'));
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Delete'), findsNothing);
      expect(find.text('Only the creator or a director can edit this event.'), findsOneWidget);
    });

    testWidgets('the plan card returns open plan', (tester) async {
      await _open(
          tester,
          (c) => showScheduleEventSheet(c,
              entry: _entry(lessonPlanId: 'lp-1'), date: _wed, subject: 'Arts', planTitle: 'Watercolours'));
      expect(find.text('Watercolours'), findsOneWidget);
      expect(find.text('Arts · Approved lesson plan'), findsOneWidget);
      await tester.tap(find.byKey(const Key('event-sheet-plan')));
      await tester.pumpAndSettle();
      expect(_out(tester), 'open plan');
    });

    testWidgets('Delete asks first; confirming returns deleted', (tester) async {
      await _open(tester, (c) => showScheduleEventSheet(c, entry: _entry(), date: _wed, canEdit: true));
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(_out(tester), 'deleted');
    });

    testWidgets('cancelling the delete keeps the sheet open', (tester) async {
      await _open(tester, (c) => showScheduleEventSheet(c, entry: _entry(), date: _wed, canEdit: true));
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Every Monday'), findsOneWidget);
      expect(_out(tester), 'none');
    });
  });

  group('edit mode', () {
    testWidgets('Edit turns the same sheet into the form, pre-filled', (tester) async {
      await _open(tester, (c) => showScheduleEventSheet(c, entry: _entry(), date: _wed, canEdit: true));
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit event'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Art'), findsOneWidget);
      expect(find.text('08:00'), findsOneWidget);
      expect(find.text('09:00'), findsOneWidget);
      // Weekly entries describe their own day, not the viewed day.
      expect(find.text('Repeats every Monday'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('Cancel returns to the summary and drops the changes', (tester) async {
      await _open(tester, (c) => showScheduleEventSheet(c, entry: _entry(), date: _wed, canEdit: true));
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('event-name')), 'Changed');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Edit event'), findsNothing);
      expect(find.text('Art'), findsOneWidget);
      expect(find.text('Changed'), findsNothing);
    });

    testWidgets('the entry colour is pre-selected and returned when untouched', (tester) async {
      await _open(tester, (c) => showScheduleEventSheet(c, entry: _entry(), date: _wed, canEdit: true));
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(_out(tester), contains('color:EF5350'));
      expect(_out(tester), contains('saved:Art|08:00-09:00'));
    });

    testWidgets('a one-off keeps its own date, not the viewed one', (tester) async {
      final jan31 = DateTime(2026, 1, 31);
      await _open(
          tester,
          (c) => showScheduleEventSheet(c,
              entry: _entry(recurrence: 'once', anchorDate: jan31), date: _wed, canEdit: true));
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Occurs once on 31 Jan 2026'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(_out(tester), contains('recurrence:once'));
      expect(_out(tester), contains('anchor:${jan31.toIso8601String()}'));
    });
  });
}
