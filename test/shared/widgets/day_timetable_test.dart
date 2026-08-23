import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/core/models/schedule.dart';
import 'package:kids_management/shared/widgets/day_timetable.dart';

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

  testWidgets('the entry block renders using the entry\'s saved color', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DayTimetable(entries: [_entry()]))),
    );

    final container = tester.widget<Container>(find.byKey(const Key('entry-block-entry-1')));
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, const Color(0xFF26A69A));
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
}
