import 'package:flutter/material.dart';
import '../../core/models/attendance.dart';

// Shared by the parent and director attendance screens — a consistent
// color mapping so "present" always reads the same way across roles.
class AttendanceStatusChip extends StatelessWidget {
  const AttendanceStatusChip({super.key, required this.status});

  final AttendanceStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, background, foreground) = switch (status) {
      AttendanceStatus.present => ('Present', Colors.green.shade100, Colors.green.shade800),
      AttendanceStatus.absent => ('Absent', Colors.red.shade100, Colors.red.shade800),
      AttendanceStatus.late => ('Late', Colors.orange.shade100, Colors.orange.shade800),
      AttendanceStatus.excused =>
        ('Excused', Colors.blueGrey.shade100, Colors.blueGrey.shade800),
    };
    return Chip(
      label: Text(label),
      backgroundColor: background,
      labelStyle: TextStyle(color: foreground, fontWeight: FontWeight.w600),
      side: BorderSide.none,
    );
  }
}
