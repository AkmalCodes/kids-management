import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawankecil/core/auth/auth_controller.dart';
import 'package:kawankecil/core/models/app_user.dart';
import 'package:kawankecil/core/models/schedule.dart';
import 'package:kawankecil/shared/widgets/day_timetable.dart';
import 'package:kawankecil/shared/widgets/schedule_agenda_view.dart';

// anchorDate is injected everywhere so tests don't depend on the real
// current date/time. It is "now": Friday 17 July 2026, 10:12. Its week is
// Mon 13 – Sun 19 July.
final _anchor = DateTime(2026, 7, 17, 10, 12);

ScheduleEntry _entry(
  String id,
  String day,
  String start,
  String end,
  String label, {
  String recurrence = 'weekly',
  DateTime? anchorDate,
  String color = '26A69A',
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
      color: color,
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
  _entry('entry-3', 'Friday', '08:00', '08:30', 'Morning circle'),
  _entry('entry-4', 'Friday', '10:00', '10:30', 'Snack time'),
  _entry('entry-5', 'Friday', '15:00', '15:45', 'Outdoor play'),
];

Widget _wrap(Widget child) =>
    ProviderScope(child: MaterialApp(home: Scaffold(body: child)));

void main() {
  testWidgets('header shows the month and a week strip with the selected day',
      (tester) async {
    await tester.pumpWidget(_wrap(ScheduleAgendaView(entries: const [], anchorDate: _anchor)));

    expect(find.text('July 2026'), findsOneWidget);
    for (var d = 13; d <= 19; d++) {
      expect(find.byKey(Key('week-day-2026-07-$d')), findsOneWidget);
    }
    expect(find.byTooltip('Pick a date'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    // Today (Friday) is selected, so its agenda heading is shown.
    expect(find.text('Friday · No activities'), findsOneWidget);
    expect(find.text('No activities on this day.'), findsOneWidget);
  });

  testWidgets('agenda lists only the selected day, sorted by start time', (tester) async {
    await tester.pumpWidget(_wrap(ScheduleAgendaView(entries: _entries, anchorDate: _anchor)));

    expect(find.text('Friday · 3 activities'), findsOneWidget);
    expect(find.text('Morning circle'), findsOneWidget);
    expect(find.text('Snack time'), findsOneWidget);
    expect(find.text('Outdoor play'), findsOneWidget);
    expect(find.text('Art'), findsNothing); // Monday's
    final y1 = tester.getTopLeft(find.text('Morning circle')).dy;
    final y2 = tester.getTopLeft(find.text('Outdoor play')).dy;
    expect(y1, lessThan(y2));
  });

  testWidgets('tapping a day in the strip switches the agenda to that day', (tester) async {
    await tester.pumpWidget(_wrap(ScheduleAgendaView(entries: _entries, anchorDate: _anchor)));

    await tester.tap(find.byKey(const Key('week-day-2026-07-13')));
    await tester.pumpAndSettle();

    expect(find.text('Monday · 1 activity'), findsOneWidget);
    expect(find.text('Art'), findsOneWidget);
    expect(find.text('Snack time'), findsNothing);
  });

  testWidgets('swiping the strip changes week; Today jumps back', (tester) async {
    await tester.pumpWidget(_wrap(ScheduleAgendaView(entries: const [], anchorDate: _anchor)));

    await tester.fling(find.byKey(const Key('week-strip')), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    // Next week; the same weekday (Friday the 24th) stays selected.
    expect(find.byKey(const Key('week-day-2026-07-20')), findsOneWidget);
    expect(find.byKey(const Key('week-day-2026-07-13')), findsNothing);

    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('week-day-2026-07-13')), findsOneWidget);
  });

  testWidgets('today: past events fade, the current one is marked Now, a now line shows',
      (tester) async {
    await tester.pumpWidget(_wrap(ScheduleAgendaView(entries: _entries, anchorDate: _anchor)));

    // 10:12 is inside Snack time (10:00–10:30).
    expect(find.text('Now'), findsOneWidget);
    expect(find.byKey(const Key('now-line')), findsOneWidget);
    // Morning circle (08:00–08:30) is over.
    final faded = tester.widget<Opacity>(find.byKey(const Key('agenda-row-entry-3')));
    expect(faded.opacity, lessThan(1));
    final current = tester.widget<Opacity>(find.byKey(const Key('agenda-row-entry-4')));
    expect(current.opacity, 1);
  });

  testWidgets('another day has no Now marker or now line', (tester) async {
    await tester.pumpWidget(_wrap(ScheduleAgendaView(entries: _entries, anchorDate: _anchor)));
    await tester.tap(find.byKey(const Key('week-day-2026-07-15')));
    await tester.pumpAndSettle();

    expect(find.text('Music'), findsOneWidget);
    expect(find.text('Now'), findsNothing);
    expect(find.byKey(const Key('now-line')), findsNothing);
  });

  testWidgets("event card's colour bar follows the entry's saved colour", (tester) async {
    final entries = [_entry('e1', 'Friday', '08:00', '09:00', 'Art', color: 'D81B60')];
    await tester.pumpWidget(_wrap(ScheduleAgendaView(entries: entries, anchorDate: _anchor)));

    final bar = tester.widget<Container>(find.byKey(const Key('event-bar-e1')));
    expect((bar.decoration as BoxDecoration).color, const Color(0xFFD81B60));
  });

  testWidgets('Timeline opens the day timetable for the selected day', (tester) async {
    await tester.pumpWidget(_wrap(ScheduleAgendaView(entries: _entries, anchorDate: _anchor)));

    await tester.tap(find.text('Timeline'));
    await tester.pumpAndSettle();

    expect(find.byType(DayTimetable), findsOneWidget);
    expect(find.text('Friday, Jul 17'), findsOneWidget);
  });

  testWidgets('tapping an event opens its day', (tester) async {
    await tester.pumpWidget(_wrap(ScheduleAgendaView(entries: _entries, anchorDate: _anchor)));

    await tester.tap(find.text('Outdoor play'));
    await tester.pumpAndSettle();

    expect(find.text('Friday, Jul 17'), findsOneWidget);
  });

  testWidgets('a once entry shows only on its anchor date', (tester) async {
    final onceEntry = _entry('once-1', 'Monday', '10:00', '11:00', 'One-off',
        recurrence: 'once', anchorDate: DateTime(2026, 7, 17));
    // Its day field ('Monday') would match Monday the 13th under a weekly
    // rule; a correct 'once' rule must not show it there.
    await tester.pumpWidget(_wrap(ScheduleAgendaView(entries: [onceEntry], anchorDate: _anchor)));
    expect(find.text('One-off'), findsOneWidget);

    await tester.tap(find.byKey(const Key('week-day-2026-07-13')));
    await tester.pumpAndSettle();
    expect(find.text('One-off'), findsNothing);
  });

  testWidgets('a daily entry shows on weekdays, not weekends', (tester) async {
    final entries = [
      _entry('d1', 'Monday', '09:00', '10:00', 'Daily Standup', recurrence: 'daily'),
    ];
    await tester.pumpWidget(_wrap(ScheduleAgendaView(entries: entries, anchorDate: _anchor)));
    expect(find.text('Daily Standup'), findsOneWidget); // Friday

    await tester.tap(find.byKey(const Key('week-day-2026-07-18')));
    await tester.pumpAndSettle();
    expect(find.text('Daily Standup'), findsNothing); // Saturday
  });

  testWidgets('no Add button when read-only', (tester) async {
    await tester.pumpWidget(_wrap(ScheduleAgendaView(entries: _entries, anchorDate: _anchor)));
    expect(find.byTooltip('Add event'), findsNothing);
  });

  testWidgets('editable: Add opens the selected day with the create dialog', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(AppUser(
              id: 'teacher-1',
              role: 'teacher',
              name: 'Teacher',
              phone: '',
              centerId: 'center-1',
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
              createdBy: 'director-1',
              updatedBy: 'director-1',
            ))),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ScheduleAgendaView(
            entries: _entries,
            anchorDate: _anchor,
            type: 'teacher',
            refId: 'teacher-1',
            centerId: 'center-1',
            editable: true,
          ),
        ),
      ),
    ));

    await tester.tap(find.byTooltip('Add event'));
    await tester.pumpAndSettle();

    expect(find.text('Friday, Jul 17'), findsOneWidget);
    expect(find.text('Create Event'), findsOneWidget);
  });

  testWidgets('fits a 360px-wide phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final entries = [
      _entry('long', 'Friday', '09:00', '10:00', 'A very long activity name that keeps going'),
    ];
    await tester.pumpWidget(_wrap(ScheduleAgendaView(entries: entries, anchorDate: _anchor)));
    expect(tester.takeException(), isNull);
  });
}
