import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_flutter/core/models/schedule.dart';
import 'package:test_flutter/shared/widgets/schedule_list.dart';

void main() {
  testWidgets('shows an empty state when there are no entries', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ScheduleList(entries: []))),
    );
    expect(find.text('No schedule set yet.'), findsOneWidget);
  });

  testWidgets('groups entries by day and sorts days Monday first', (tester) async {
    const entries = [
      ScheduleEntry(day: 'Wednesday', startTime: '10:00', endTime: '11:00', label: 'Music'),
      ScheduleEntry(day: 'Monday', startTime: '08:00', endTime: '09:00', label: 'Art'),
      ScheduleEntry(day: 'Monday', startTime: '09:30', endTime: '10:00', label: 'Nap'),
    ];

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ScheduleList(entries: entries))),
    );

    expect(find.text('Monday'), findsOneWidget);
    expect(find.text('Wednesday'), findsOneWidget);
    expect(find.text('Art'), findsOneWidget);
    expect(find.text('Nap'), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);

    // Monday's card should render before Wednesday's.
    final mondayY = tester.getTopLeft(find.text('Monday')).dy;
    final wednesdayY = tester.getTopLeft(find.text('Wednesday')).dy;
    expect(mondayY, lessThan(wednesdayY));
  });
}
