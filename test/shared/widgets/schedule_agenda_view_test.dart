import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/core/models/schedule.dart';
import 'package:kids_management/shared/widgets/day_timetable.dart';
import 'package:kids_management/shared/widgets/schedule_agenda_view.dart';

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

  testWidgets('monthly entry shows on exactly one day row in month view',
      (tester) async {
    // Anchor day 15; in July, this is the 15th. In February, it would be the
    // 15th too (28/29 > 15, so no clamping).
    final entries = [
      _entry(
        'entry-monthly',
        'Friday', // day field is unused for monthly, but required
        '10:00',
        '11:00',
        'Monthly Meeting',
        recurrence: 'monthly',
        anchorDate: DateTime(2026, 7, 15),
      ),
    ];
    await tester.pumpWidget(
      _wrap(ScheduleAgendaView(entries: entries, anchorDate: _anchor)),
    );

    // Switch to month view (July 2026).
    await tester.tap(find.byTooltip('Month view'));
    await tester.pumpAndSettle();

    // Scroll to the 15th to ensure it's rendered (ListView is lazy).
    await tester.scrollUntilVisible(find.text('15'), 200);

    // The entry should appear exactly once, on the 15th.
    expect(find.text('Monthly Meeting'), findsOneWidget);
  });

  testWidgets('annually entry on Feb 29 shows on Feb 28 in common year',
      (tester) async {
    // Anchor on Feb 29, 2024 (a leap year).
    // When we view February 2026 (a common year), it should show on the 28th.
    final entries = [
      _entry(
        'entry-annual',
        'Thursday', // day field is unused for annual
        '14:00',
        '15:00',
        'Annual Celebration',
        recurrence: 'annually',
        anchorDate: DateTime(2024, 2, 29),
      ),
    ];
    // Inject an anchor date in February 2026 (a common year: 28 days).
    await tester.pumpWidget(
      _wrap(ScheduleAgendaView(entries: entries, anchorDate: DateTime(2026, 2, 15))),
    );

    // Switch to month view (February 2026).
    await tester.tap(find.byTooltip('Month view'));
    await tester.pumpAndSettle();

    // Scroll to the 28th to ensure it's rendered (ListView is lazy).
    await tester.scrollUntilVisible(find.text('28'), 200);

    // The entry should appear exactly once, on the 28th.
    expect(find.text('Annual Celebration'), findsOneWidget);
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
