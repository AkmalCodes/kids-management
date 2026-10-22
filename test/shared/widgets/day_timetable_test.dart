import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawankecil/core/models/schedule.dart';
import 'package:kawankecil/shared/widgets/day_timetable.dart';

ScheduleEntry _entry() => ScheduleEntry(
  id: 'entry-1',
  type: 'teacher',
  refId: 'teacher-1',
  centerId: 'center-1',
  day: 'Monday',
  startTime: '08:00', // grid starts at 07:00, so this block spans hour row 1
  endTime: '09:00',
  label: 'Art',
  color: '26A69A',
  recurrence: 'weekly',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'teacher-1',
  updatedBy: 'teacher-1',
);

void main() {
  testWidgets('with no callbacks, tapping does nothing (read-only)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DayTimetable(entries: [_entry()]))),
    );

    final gridTopLeft = tester.getTopLeft(find.byKey(const Key('day-timetable-grid')));
    // Tap inside the Art block (hour 8, i.e. row 1 of the grid).
    await tester.tapAt(gridTopLeft + const Offset(10, 56 + 10));
    await tester.pump();
    // Nothing to assert beyond "no exception" — read-only means no handlers exist.
  });

  testWidgets('tapping an existing entry calls onTapEntry with that entry', (tester) async {
    ScheduleEntry? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DayTimetable(
            entries: [_entry()],
            onTapEntry: (entry) => tapped = entry,
          ),
        ),
      ),
    );

    final gridTopLeft = tester.getTopLeft(find.byKey(const Key('day-timetable-grid')));
    // 08:00–09:00 is hour row index 1 (grid starts at 07:00) -> y in [56, 112).
    await tester.tapAt(gridTopLeft + const Offset(10, 70));
    await tester.pump();

    expect(tapped?.label, 'Art');
  });

  testWidgets('tapping empty space calls onAddEntry with the tapped hour', (tester) async {
    int? tappedHour;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DayTimetable(
            entries: const [],
            onAddEntry: (hour) => tappedHour = hour,
          ),
        ),
      ),
    );

    final gridTopLeft = tester.getTopLeft(find.byKey(const Key('day-timetable-grid')));
    // Hour row index 3 (grid starts at 07:00) -> 10:00, y in [168, 224).
    await tester.tapAt(gridTopLeft + const Offset(10, 180));
    await tester.pump();

    expect(tappedHour, 10);
  });

  testWidgets('the entry block is a pale tint of its colour with a solid colour bar',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DayTimetable(entries: [_entry()]))),
    );

    final bar = tester.widget<Container>(find.byKey(const Key('entry-bar-entry-1')));
    expect((bar.decoration as BoxDecoration).color, const Color(0xFF26A69A));
    final block = tester.widget<Container>(find.byKey(const Key('entry-block-entry-1')));
    final bg = (block.decoration as BoxDecoration).color!;
    expect(bg.a, lessThan(0.3)); // a light wash, not the solid colour
  });

  testWidgets('nowTime draws the now line; finished blocks fade', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: DayTimetable(entries: [_entry()], nowTime: '09:30')),
        ),
      ),
    );

    expect(find.byKey(const Key('timetable-now-line')), findsOneWidget);
    final fade = tester.widget<Opacity>(find.byKey(const Key('entry-fade-entry-1')));
    expect(fade.opacity, lessThan(1)); // 08:00-09:00 is over at 09:30
  });

  testWidgets('no nowTime (another day): no now line, nothing faded', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: DayTimetable(entries: [_entry()]))),
      ),
    );

    expect(find.byKey(const Key('timetable-now-line')), findsNothing);
    final fade = tester.widget<Opacity>(find.byKey(const Key('entry-fade-entry-1')));
    expect(fade.opacity, 1);
  });

  testWidgets('the block matching newEntryId fades in', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DayTimetable(entries: [_entry()], newEntryId: 'entry-1')),
      ),
    );

    expect(find.byType(TweenAnimationBuilder<double>), findsOneWidget);
  });

  testWidgets('a block that is not the newEntryId does not animate', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DayTimetable(entries: [_entry()], newEntryId: 'some-other-id')),
      ),
    );

    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
  });

  testWidgets('no newEntryId means no block animates', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DayTimetable(entries: [_entry()]))),
    );

    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
  });

  testWidgets('the grid runs from 07:00 to a last 19:00 row', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: DayTimetable(entries: const []))),
      ),
    );
    expect(find.text('07:00'), findsOneWidget);
    expect(find.text('19:00'), findsOneWidget);
    expect(find.text('20:00'), findsNothing);
  });
}
