import 'package:flutter/material.dart';
import '../../core/models/lesson_plan.dart';

// Consistent colour/label for a lesson plan's approval state, shown on the
// teacher and director lists + the editor.
//
// Style from screen design A (Figma page "Screen designs"): a small pill
// with a coloured dot. Each status has its own meaning-colour (grey draft,
// amber waiting, green approved, red needs changes) rather than brand pink,
// so status scans at a glance and doesn't blend into the rest of the UI.
//
// "Rejected" is shown as "Needs changes": it tells the teacher what to do
// next instead of just delivering a verdict. The status value in the
// database is still `rejected`.
class LessonPlanStatusChip extends StatelessWidget {
  const LessonPlanStatusChip({super.key, required this.status});

  final LessonPlanStatus status;

  // (background, foreground) for a status. Public so other widgets (the
  // feedback strip on a list card, the editor's banner) use the same tones.
  static (Color, Color) colorsFor(LessonPlanStatus status) => switch (status) {
        LessonPlanStatus.draft => (const Color(0xFFEEEAEB), const Color(0xFF5F5A5C)),
        LessonPlanStatus.submitted => (const Color(0xFFFFF1D6), const Color(0xFF8A5300)),
        LessonPlanStatus.approved => (const Color(0xFFE3F4EA), const Color(0xFF2E7D4F)),
        LessonPlanStatus.rejected => (const Color(0xFFFDE7E4), const Color(0xFFB3261E)),
      };

  static String labelFor(LessonPlanStatus status) => switch (status) {
        LessonPlanStatus.draft => 'Draft',
        LessonPlanStatus.submitted => 'Awaiting approval',
        LessonPlanStatus.approved => 'Approved',
        LessonPlanStatus.rejected => 'Needs changes',
      };

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = colorsFor(status);
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 4, 10, 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999), // fully rounded pill
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: foreground, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            labelFor(status),
            style: TextStyle(
              color: foreground,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
