import 'package:flutter/material.dart';
import '../../core/models/lesson_plan.dart';

// Read-only view of an (approved) lesson plan, opened by tapping a schedule
// event that has one attached (§6.5). For a viewer here only the subject (the
// heading, e.g. "Maths") and the content matter -- the approval status isn't
// shown. No editing; that's the teacher/director LessonPlanEditScreen.
class LessonPlanViewScreen extends StatelessWidget {
  const LessonPlanViewScreen({super.key, required this.plan, this.subjectName});

  final LessonPlan plan;
  final String? subjectName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The subject is the headline (falls back to the plan title if untagged).
    final heading = subjectName ?? plan.title;
    return Scaffold(
      appBar: AppBar(title: Text(heading)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(heading, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
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
