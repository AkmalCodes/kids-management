import 'package:flutter/material.dart';
import '../../core/models/schedule.dart';
import '../widgets/day_timetable.dart';

// Pushed by ScheduleAgendaView when a day row is tapped. Receives the
// already-filtered entries for that day, so it has no data dependencies
// of its own — just renders.
class DayScheduleScreen extends StatelessWidget {
  const DayScheduleScreen({super.key, required this.date, required this.entries});

  final DateTime date;
  final List<ScheduleEntry> entries;

  static const _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];
  static const _monthAbbrev = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final title =
        '${_weekdayNames[date.weekday - 1]}, ${_monthAbbrev[date.month - 1]} ${date.day}';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: entries.isEmpty
          ? const Center(child: Text('No events on this day.'))
          : SingleChildScrollView(child: DayTimetable(entries: entries)),
    );
  }
}
