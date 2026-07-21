import 'package:flutter_test/flutter_test.dart';
import 'package:test_flutter/core/models/schedule.dart';

void main() {
  group('ScheduleEntry', () {
    final json = {
      'id': 'entry-1',
      'type': 'teacher',
      'ref_id': 'teacher-1',
      'center_id': 'center-1',
      'day': 'Monday',
      'start_time': '08:00',
      'end_time': '09:00',
      'label': 'Art',
      'created_at': '2026-07-01T00:00:00.000Z',
      'updated_at': '2026-07-01T00:00:00.000Z',
      'created_by': 'teacher-1',
      'updated_by': 'teacher-1',
    };

    test('fromJson parses all fields', () {
      final entry = ScheduleEntry.fromJson(json);
      expect(entry.id, 'entry-1');
      expect(entry.type, 'teacher');
      expect(entry.refId, 'teacher-1');
      expect(entry.centerId, 'center-1');
      expect(entry.day, 'Monday');
      expect(entry.startTime, '08:00');
      expect(entry.endTime, '09:00');
      expect(entry.label, 'Art');
      expect(entry.createdBy, 'teacher-1');
      expect(entry.updatedBy, 'teacher-1');
    });

    test('toJson serializes writable fields and omits id/timestamps', () {
      final entry = ScheduleEntry.fromJson(json);
      final out = entry.toJson();
      expect(out['type'], 'teacher');
      expect(out['ref_id'], 'teacher-1');
      expect(out['center_id'], 'center-1');
      expect(out['day'], 'Monday');
      expect(out['start_time'], '08:00');
      expect(out['end_time'], '09:00');
      expect(out['label'], 'Art');
      expect(out['created_by'], 'teacher-1');
      expect(out['updated_by'], 'teacher-1');
      expect(out.containsKey('id'), isFalse);
      expect(out.containsKey('created_at'), isFalse);
    });

    test('canBeEditedBy is true for the creator', () {
      final entry = ScheduleEntry.fromJson(json);
      expect(entry.canBeEditedBy(uid: 'teacher-1', role: 'teacher'), isTrue);
    });

    test('canBeEditedBy is true for any director', () {
      final entry = ScheduleEntry.fromJson(json);
      expect(entry.canBeEditedBy(uid: 'director-1', role: 'director'), isTrue);
    });

    test('canBeEditedBy is false for a different teacher', () {
      final entry = ScheduleEntry.fromJson(json);
      expect(entry.canBeEditedBy(uid: 'teacher-2', role: 'teacher'), isFalse);
    });
  });
}
