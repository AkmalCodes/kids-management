import 'package:flutter_test/flutter_test.dart';
import 'package:test_flutter/core/models/schedule.dart';

void main() {
  group('ScheduleEntry', () {
    final json = {
      'day': 'Monday',
      'start_time': '08:00',
      'end_time': '09:00',
      'label': 'Art',
    };

    test('fromJson parses all fields', () {
      final entry = ScheduleEntry.fromJson(json);
      expect(entry.day, 'Monday');
      expect(entry.startTime, '08:00');
      expect(entry.endTime, '09:00');
      expect(entry.label, 'Art');
    });

    test('toJson serializes all fields', () {
      const entry = ScheduleEntry(
        day: 'Monday',
        startTime: '08:00',
        endTime: '09:00',
        label: 'Art',
      );
      expect(entry.toJson(), json);
    });
  });

  group('Schedule', () {
    final json = {
      'id': 'sched-1',
      'type': 'teacher',
      'ref_id': 'teacher-1',
      'center_id': 'center-1',
      'entries': [
        {'day': 'Monday', 'start_time': '08:00', 'end_time': '09:00', 'label': 'Art'},
      ],
      'created_at': '2026-07-01T00:00:00.000Z',
      'updated_at': '2026-07-01T00:00:00.000Z',
      'created_by': 'director-1',
      'updated_by': 'director-1',
    };

    test('fromJson parses entries and metadata', () {
      final schedule = Schedule.fromJson(json);
      expect(schedule.id, 'sched-1');
      expect(schedule.type, 'teacher');
      expect(schedule.refId, 'teacher-1');
      expect(schedule.centerId, 'center-1');
      expect(schedule.entries, hasLength(1));
      expect(schedule.entries.first.label, 'Art');
      expect(schedule.createdBy, 'director-1');
    });

    test('toJson serializes entries and omits id/timestamps', () {
      final schedule = Schedule.fromJson(json);
      final out = schedule.toJson();
      expect(out['type'], 'teacher');
      expect(out['ref_id'], 'teacher-1');
      expect(out['entries'], [
        {'day': 'Monday', 'start_time': '08:00', 'end_time': '09:00', 'label': 'Art'},
      ]);
      expect(out.containsKey('id'), isFalse);
    });
  });
}
