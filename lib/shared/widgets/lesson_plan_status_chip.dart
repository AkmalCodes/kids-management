import 'package:flutter/material.dart';
import '../../core/models/lesson_plan.dart';

// Consistent color/label for a lesson plan's approval state, shown on the
// teacher and director lists + the editor. Same shape as AttendanceStatusChip.
class LessonPlanStatusChip extends StatelessWidget {
  const LessonPlanStatusChip({super.key, required this.status});

  final LessonPlanStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, background, foreground) = switch (status) {
      LessonPlanStatus.draft => ('Draft', Colors.grey.shade300, Colors.grey.shade800),
      LessonPlanStatus.submitted =>
        ('Awaiting approval', Colors.orange.shade100, Colors.orange.shade800),
      LessonPlanStatus.approved => ('Approved', Colors.green.shade100, Colors.green.shade800),
      LessonPlanStatus.rejected => ('Rejected', Colors.red.shade100, Colors.red.shade800),
    };
    return Chip(
      label: Text(label),
      backgroundColor: background,
      labelStyle: TextStyle(color: foreground, fontWeight: FontWeight.w600),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}
