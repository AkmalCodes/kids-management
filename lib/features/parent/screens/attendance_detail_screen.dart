import 'package:flutter/material.dart';
import '../../../core/models/attendance.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/util/date_display.dart';
import '../../../shared/widgets/attendance_day_details.dart';

// One day of a child's attendance for the parent (screen design AA6): the
// status and arrival time, both photos large, and the teacher's note. The
// body is the shared AttendanceDayDetails, so the parent sees exactly what
// the director sees for the same day.
class AttendanceDetailScreen extends StatelessWidget {
  const AttendanceDetailScreen({super.key, required this.record, required this.childName});

  final Attendance record;
  final String childName;

  @override
  Widget build(BuildContext context) {
    final day = DateTime.tryParse(record.date);
    return Scaffold(
      appBar: AppBar(title: Text(day == null ? record.date : longDayLabel(day))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(childName,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.mutedText)),
          const SizedBox(height: 10),
          AttendanceDayDetails(record: record),
        ],
      ),
    );
  }
}
