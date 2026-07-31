import 'package:flutter_test/flutter_test.dart';
import 'package:test_flutter/core/models/lesson_plan.dart';

void main() {
  Map<String, dynamic> baseJson() => {
        'id': 'lp-1',
        'teacher_id': 'teacher-1',
        'center_id': 'center-1',
        'title': 'Colours',
        'date': '2026-08-03',
        'content': 'Watercolours',
        'created_at': '2026-08-01T00:00:00Z',
        'updated_at': '2026-08-01T00:00:00Z',
      };

  test('fromJson parses required fields and defaults status to draft', () {
    final plan = LessonPlan.fromJson(baseJson());
    expect(plan.id, 'lp-1');
    expect(plan.title, 'Colours');
    expect(plan.status, LessonPlanStatus.draft);
    expect(plan.subjectId, isNull);
    expect(plan.classId, isNull);
    expect(plan.reviewedAt, isNull);
  });

  test('fromJson maps status, subject, class, and review fields', () {
    final plan = LessonPlan.fromJson({
      ...baseJson(),
      'status': 'approved',
      'subject_id': 'sub-1',
      'class_id': 'class-1',
      'reviewed_by': 'director-1',
      'reviewed_at': '2026-08-02T09:00:00Z',
      'review_note': 'Looks good',
    });
    expect(plan.status, LessonPlanStatus.approved);
    expect(plan.subjectId, 'sub-1');
    expect(plan.classId, 'class-1');
    expect(plan.reviewedBy, 'director-1');
    expect(plan.reviewNote, 'Looks good');
  });

  test('unknown status string falls back to draft', () {
    final plan = LessonPlan.fromJson({...baseJson(), 'status': 'bananas'});
    expect(plan.status, LessonPlanStatus.draft);
  });
}
