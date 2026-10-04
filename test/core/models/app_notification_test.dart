import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/core/models/app_notification.dart';

void main() {
  Map<String, dynamic> baseJson() => {
        'id': 'n-1',
        'user_id': 'director-1',
        'type': 'lesson_plan',
        'status': 'SUBMITTED',
        'title': 'Lesson plan submitted',
        'body': 'Ms. Smith submitted "Colours" for review',
        'entity_id': 'lp-1',
        'created_at': '2026-09-15T09:00:00Z',
      };

  test('fromJson parses required fields with read_at/created_by absent', () {
    final n = AppNotification.fromJson(baseJson());
    expect(n.id, 'n-1');
    expect(n.userId, 'director-1');
    expect(n.type, 'lesson_plan');
    expect(n.status, 'SUBMITTED');
    expect(n.title, 'Lesson plan submitted');
    expect(n.body, 'Ms. Smith submitted "Colours" for review');
    expect(n.entityId, 'lp-1');
    expect(n.readAt, isNull);
    expect(n.createdBy, isNull);
  });

  test('fromJson parses read_at and created_by when present', () {
    final n = AppNotification.fromJson({
      ...baseJson(),
      'read_at': '2026-09-15T10:00:00Z',
      'created_by': 'teacher-1',
    });
    expect(n.readAt, DateTime.parse('2026-09-15T10:00:00Z'));
    expect(n.createdBy, 'teacher-1');
  });
}
