import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/core/models/attendance.dart';
import 'package:kids_management/core/models/staff_attendance.dart';

void main() {
  group('StaffAttendance', () {
    final json = {
      'id': 'sa-1',
      'staff_id': 'teacher-1',
      'center_id': 'center-1',
      'date': '2026-09-02',
      'status': 'present',
      'notes': '',
      'created_at': '2026-09-02T00:00:00.000Z',
      'updated_at': '2026-09-02T00:00:00.000Z',
      'created_by': 'teacher-1',
      'updated_by': 'teacher-1',
    };

    test('fromJson parses status enum from string', () {
      final record = StaffAttendance.fromJson(json);
      expect(record.staffId, 'teacher-1');
      expect(record.centerId, 'center-1');
      expect(record.date, '2026-09-02');
      expect(record.status, AttendanceStatus.present);
      expect(record.createdBy, 'teacher-1');
    });

    test('toJson serializes status enum as its name and omits id', () {
      final record = StaffAttendance.fromJson(json);
      final out = record.toJson();
      expect(out['status'], 'present');
      expect(out['staff_id'], 'teacher-1');
      expect(out.containsKey('id'), isFalse);
    });

    test('fromJson handles each AttendanceStatus value', () {
      for (final status in AttendanceStatus.values) {
        final withStatus = Map<String, dynamic>.from(json)..['status'] = status.name;
        expect(StaffAttendance.fromJson(withStatus).status, status);
      }
    });

    test('fromJson defaults notes to empty string when absent', () {
      final withoutNotes = Map<String, dynamic>.from(json)..remove('notes');
      expect(StaffAttendance.fromJson(withoutNotes).notes, '');
    });

    test('fromJson parses clock_in_at and clock_out_at when present', () {
      final withClocks = Map<String, dynamic>.from(json)
        ..['clock_in_at'] = '2026-09-02T06:30:00.000Z'
        ..['clock_out_at'] = '2026-09-02T15:00:00.000Z';
      final record = StaffAttendance.fromJson(withClocks);
      expect(record.clockInAt, DateTime.utc(2026, 9, 2, 6, 30));
      expect(record.clockOutAt, DateTime.utc(2026, 9, 2, 15, 0));
    });

    test('fromJson leaves clock times null when the columns are null or absent', () {
      final withNulls = Map<String, dynamic>.from(json)
        ..['clock_in_at'] = null
        ..['clock_out_at'] = null;
      expect(StaffAttendance.fromJson(withNulls).clockInAt, isNull);
      expect(StaffAttendance.fromJson(withNulls).clockOutAt, isNull);
      // `json` itself has neither key -- absent must behave like null.
      expect(StaffAttendance.fromJson(json).clockInAt, isNull);
      expect(StaffAttendance.fromJson(json).clockOutAt, isNull);
    });
  });
}
