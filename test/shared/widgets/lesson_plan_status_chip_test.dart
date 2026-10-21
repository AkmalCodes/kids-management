import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawankecil/core/models/lesson_plan.dart';
import 'package:kawankecil/shared/widgets/lesson_plan_status_chip.dart';

void main() {
  testWidgets('labels: rejected reads as an action, not a verdict', (tester) async {
    for (final (status, label) in [
      (LessonPlanStatus.draft, 'Draft'),
      (LessonPlanStatus.submitted, 'Awaiting approval'),
      (LessonPlanStatus.approved, 'Approved'),
      (LessonPlanStatus.rejected, 'Needs changes'),
    ]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: LessonPlanStatusChip(status: status))));
      expect(find.text(label), findsOneWidget, reason: '$status');
    }
  });
}
