import 'package:flutter/material.dart';
import '../../core/models/lesson_plan.dart';
import '../../shared/widgets/lesson_plan_status_chip.dart';

// Read-only view of an (approved) lesson plan, opened by tapping a schedule
// event that has one attached (§6.5). Shows the subject, title and content --
// no editing here; that's the teacher/director LessonPlanEditScreen.
class LessonPlanViewScreen extends StatelessWidget {
  const LessonPlanViewScreen({super.key, required this.plan, this.subjectName});

  final LessonPlan plan;
  final String? subjectName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(plan.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              LessonPlanStatusChip(status: plan.status),
              if (subjectName != null) ...[
                const SizedBox(width: 8),
                Chip(
                  avatar: const Icon(Icons.category_outlined, size: 18),
                  label: Text(subjectName!),
                  side: BorderSide.none,
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Text('Content', style: theme.textTheme.labelMedium?.copyWith(color: theme.hintColor)),
          const SizedBox(height: 4),
          Text(
            plan.content.isEmpty ? 'No content.' : plan.content,
            style: plan.content.isEmpty
                ? theme.textTheme.bodyLarge?.copyWith(color: theme.disabledColor)
                : theme.textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}
