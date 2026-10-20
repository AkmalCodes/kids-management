import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawankecil/core/models/schedule.dart';
import 'package:kawankecil/shared/widgets/day_timetable.dart';
import 'package:kawankecil/shared/widgets/schedule_agenda_view.dart';

// anchorDate is injected everywhere so tests don't depend on the real
// current date (July has 31 days; February doesn't — a test that relies
// on DateTime.now() would break depending on when it runs).
final _anchor = DateTime(2026, 7, 17); // a Friday; its week = Jul 13–19

ScheduleEntry _entry(
  String id,
  String day,
  String start,
  String end,
  String label, {
  String recurrence = 'weekly',
  DateTime? anchorDate,
}) =>
    ScheduleEntry(
      id: id,
      type: 'teacher',
      refId: 'teacher-1',
      centerId: 'center-1',
      day: day,
      startTime: start,
      endTime: end,
      label: label,
      color: '26A69A',
      recurrence: recurrence,
      anchorDate: anchorDate,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      createdBy: 'teacher-1',
      updatedBy: 'teacher-1',
    );

final _entries = [
  _entry('entry-1', 'Monday', '08:00', '09:00', 'Art'),
  _entry('entry-2', 'Wednesday', '10:00', '11:00', 'Music'),
];

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('still renders the week grid with No events when there are no entries',
      (tester) async {
    await tester.pumpWidget(
      _wrap(ScheduleAgendaView(entries: const [], anchorDate: _anchor)),
    );
    // The toggle and all 7 day rows must render regardless of data —
    // only the per-day content falls back to "No events".
    expect(find.byTooltip('Month view'), findsOneWidget);
    expect(find.text('No events'), findsNWidgets(7));
    expect(find.text('13'), findsOneWidget); // Monday's date number
  });

  testWidgets('week view shows 7 day rows with events and No events placeholders',
      (tester) async {
    await tester.pumpWidget(
      _wrap(ScheduleAgendaView(entries: _entries, anchorDate: _anchor)),
    );

    // Week of Jul 13–19: Monday the 13th has Art, Wednesday the 15th has
    // Music, the other 5 days are empty.
    expect(find.text('Art'), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);
    expect(find.text('No events'), findsNWidgets(5));
    expect(find.text('13'), findsOneWidget); // Monday's date number
    expect(find.text('Mon'), findsOneWidget);
  });

  testWidgets('toggle switches to month view showing every day of the month',
      (tester) async {
    await tester.pumpWidget(
      _wrap(ScheduleAgendaView(entries: _entries, anchorDate: _anchor)),
    );

    await tester.tap(find.byTooltip('Month view'));
    await tester.pumpAndSettle();

    expect(find.text('July 2026'), findsOneWidget);
    // ListView builds rows lazily, so off-screen days don't exist yet —
    // scroll to the last day of July to prove the whole month is there.
    await tester.scrollUntilVisible(find.text('31'), 200);
    expect(find.text('31'), findsOneWidget);
  });

  testWidgets('next/prev move the week; month view moves by month', (tester) async {
    await tester.pumpWidget(
      _wrap(ScheduleAgendaView(entries: const [], anchorDate: _anchor)),
    );

    // Week view: next advances Jul 13–19 -> Jul 20–26.
    await tester.tap(find.byTooltip('Next week'));
    await tester.pumpAndSettle();
    expect(find.text('20'), findsOneWidget); // Monday of the next week

    // Back to the original week.
    await tester.tap(find.byTooltip('Previous week'));
    await tester.pumpAndSettle();
    expect(find.text('13'), findsOneWidget);

    // Month view: next month -> August 2026.
    await tester.tap(find.byTooltip('Month view'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('August 2026'), findsOneWidget);
  });

  testWidgets('tapping a day row opens that day timetable page', (tester) async {
    await tester.pumpWidget(
      _wrap(ScheduleAgendaView(entries: _entries, anchorDate: _anchor)),
    );

    await tester.tap(find.text('Art'));
    await tester.pumpAndSettle();

    expect(find.byType(DayTimetable), findsOneWidget);
    expect(find.text('Monday, Jul 13'), findsOneWidget);
  });

  testWidgets('event card color follows the entry\'s saved color', (tester) async {
    final entries = [_entry('entry-1', 'Monday', '08:00', '09:00', 'Art')];
    await tester.pumpWidget(
      _wrap(ScheduleAgendaView(entries: entries, anchorDate: _anchor)),
    );

    final container = tester.widget<Container>(find.byKey(const Key('event-card-entry-1')));
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, const Color(0xFF26A69A));
  });

  testWidgets('a once entry shows only on its anchor date', (tester) async {
    // _anchor is a fixed injected "today"; put the once entry on a visible day.
    final onceEntry = _entry('once-1', 'Monday', '10:00', '11:00', 'One-off',
        recurrence: 'once', anchorDate: _anchor);
    // A second once entry whose anchor is well outside the visible week. Its
    // day field ('Monday') matches visible Monday the 13th, so a once->weekly
    // fallback bug would render it there; a correct 'once' rule must not.
    final farOnceEntry = _entry(
        'once-2', 'Monday', '12:00', '13:00', 'Far-off',
        recurrence: 'once', anchorDate: _anchor.add(const Duration(days: 30)));
    await tester.pumpWidget(
      _wrap(ScheduleAgendaView(
          entries: [onceEntry, farOnceEntry], anchorDate: _anchor)),
    );
    // Week view (default): shows exactly once, on the _anchor day.
    expect(find.text('One-off'), findsOneWidget);
    // The out-of-week once entry must not appear at all.
    expect(find.text('Far-off'), findsNothing);
  });

  testWidgets('daily entry shows on all five weekday rows in week view',
      (tester) async {
    final entries = [
      _entry(
        'entry-daily',
        'Monday', // day field is unused for daily
        '09:00',
        '10:00',
        'Daily Standup',
        recurrence: 'daily',
      ),
    ];
    await tester.pumpWidget(
      _wrap(ScheduleAgendaView(entries: entries, anchorDate: _anchor)),
    );

    // Week view is the default. July 13–19, 2026: Monday–Friday.
    // The daily entry should appear on all 5 weekday rows.
    expect(find.text('Daily Standup'), findsNWidgets(5));
    // Confirm no extra instances on weekends.
    expect(find.text('No events'), findsNWidgets(2)); // Saturday and Sunday
  });

  testWidgets('weekly entry shows only on its weekday (regression)',
      (tester) async {
    final entries = [
      _entry('entry-weekly', 'Wednesday', '10:00', '11:00', 'Weekly Sync',
          recurrence: 'weekly'),
    ];
    await tester.pumpWidget(
      _wrap(ScheduleAgendaView(entries: entries, anchorDate: _anchor)),
    );

    // Week view: July 13–19. Wednesday is the 17th.
    expect(find.text('Weekly Sync'), findsOneWidget);
    // The other 6 days should be empty.
    expect(find.text('No events'), findsNWidgets(6));
  });
}
