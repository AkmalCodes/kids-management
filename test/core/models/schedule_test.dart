import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawankecil/core/models/schedule.dart';

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
      'color': 'D81B60',
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
      expect(entry.color, 'D81B60');
      expect(entry.createdBy, 'teacher-1');
      expect(entry.updatedBy, 'teacher-1');
    });

    test('fromJson falls back to the default color when missing', () {
      final withoutColor = Map<String, dynamic>.from(json)..remove('color');
      final entry = ScheduleEntry.fromJson(withoutColor);
      expect(entry.color, '26A69A');
    });

    test('displayColor converts the stored hex into an opaque Color', () {
      final entry = ScheduleEntry.fromJson(json);
      expect(entry.displayColor, const Color(0xFFD81B60));
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
      expect(out['color'], 'D81B60');
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

    group('recurrence + anchorDate', () {
      test('fromJson reads recurrence and anchor_date when present', () {
        final withRecurrence = Map<String, dynamic>.from(json)
          ..['recurrence'] = 'once'
          ..['anchor_date'] = '2026-01-31';
        final entry = ScheduleEntry.fromJson(withRecurrence);
        expect(entry.recurrence, 'once');
        expect(entry.anchorDate, DateTime(2026, 1, 31));
      });

      test('fromJson defaults recurrence to weekly and anchorDate to null when absent', () {
        // The base fixture has neither key.
        final entry = ScheduleEntry.fromJson(json);
        expect(entry.recurrence, 'weekly');
        expect(entry.anchorDate, isNull);
      });

      test('fromJson tolerates an explicit null anchor_date', () {
        final explicitNull = Map<String, dynamic>.from(json)
          ..['recurrence'] = 'daily'
          ..['anchor_date'] = null;
        final entry = ScheduleEntry.fromJson(explicitNull);
        expect(entry.recurrence, 'daily');
        expect(entry.anchorDate, isNull);
      });

      test('toJson round-trips recurrence and anchor_date (date-only string)', () {
        final source = Map<String, dynamic>.from(json)
          ..['recurrence'] = 'daily'
          ..['anchor_date'] = '2024-02-29';
        final out = ScheduleEntry.fromJson(source).toJson();
        expect(out['recurrence'], 'daily');
        expect(out['anchor_date'], '2024-02-29');
      });

      test('toJson writes a null anchor_date when anchorDate is null', () {
        final entry = ScheduleEntry.fromJson(json); // no anchor_date
        final out = entry.toJson();
        expect(out['recurrence'], 'weekly');
        expect(out.containsKey('anchor_date'), isTrue);
        expect(out['anchor_date'], isNull);
      });
    });
  });
}
