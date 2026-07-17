import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_flutter/core/models/schedule.dart';
import 'package:test_flutter/shared/widgets/day_timetable.dart';
import 'package:test_flutter/shared/widgets/schedule_agenda_view.dart';

// anchorDate is injected everywhere so tests don't depend on the real
// current date (July has 31 days; February doesn't — a test that relies
// on DateTime.now() would break depending on when it runs).
final _anchor = DateTime(2026, 7, 17); // a Friday; its week = Jul 13–19

const _entries = [
  ScheduleEntry(day: 'Monday', startTime: '08:00', endTime: '09:00', label: 'Art'),
  ScheduleEntry(day: 'Wednesday', startTime: '10:00', endTime: '11:00', label: 'Music'),
];

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows an empty state when there are no entries at all', (tester) async {
    await tester.pumpWidget(
      _wrap(ScheduleAgendaView(entries: const [], anchorDate: _anchor)),
    );
    expect(find.text('No schedule set yet.'), findsOneWidget);
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

  testWidgets('tapping a day row opens that day timetable page', (tester) async {
    await tester.pumpWidget(
      _wrap(ScheduleAgendaView(entries: _entries, anchorDate: _anchor)),
    );

    await tester.tap(find.text('Art'));
    await tester.pumpAndSettle();

    expect(find.byType(DayTimetable), findsOneWidget);
    expect(find.text('Monday, Jul 13'), findsOneWidget);
  });
}
