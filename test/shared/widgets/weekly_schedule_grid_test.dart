import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_flutter/core/models/schedule.dart';
import 'package:test_flutter/shared/widgets/weekly_schedule_grid.dart';

void main() {
  testWidgets('shows an empty state when there are no entries', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: WeeklyScheduleGrid(entries: []))),
    );
    expect(find.text('No schedule set yet.'), findsOneWidget);
  });

  testWidgets('renders day abbreviations and entry labels as positioned blocks',
      (tester) async {
    const entries = [
      ScheduleEntry(day: 'Monday', startTime: '08:00', endTime: '09:00', label: 'Art'),
      ScheduleEntry(day: 'Wednesday', startTime: '10:00', endTime: '11:00', label: 'Music'),
    ];

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: WeeklyScheduleGrid(entries: entries))),
    );

    // Day header row shows abbreviations, not full names.
    expect(find.text('Mon'), findsOneWidget);
    expect(find.text('Wed'), findsOneWidget);
    expect(find.text('Monday'), findsNothing);

    expect(find.text('Art'), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);

    // Art's block should sit above Music's block (08:00 vs 10:00).
    final artTop = tester.getTopLeft(find.text('Art')).dy;
    final musicTop = tester.getTopLeft(find.text('Music')).dy;
    expect(artTop, lessThan(musicTop));
  });
}
