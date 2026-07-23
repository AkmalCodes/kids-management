import 'package:flutter_test/flutter_test.dart';
import 'package:test_flutter/core/models/attendance.dart';

void main() {
  group('Attendance', () {
    final json = {
      'id': 'att-1',
      'child_id': 'child-1',
      'center_id': 'center-1',
      'date': '2026-07-01',
      'status': 'present',
      'notes': '',
      'photo_path': 'child-1/2026-07-01.jpg',
      'belongings_photo_path': 'child-1/2026-07-01-belongings.jpg',
      'created_at': '2026-07-01T00:00:00.000Z',
      'updated_at': '2026-07-01T00:00:00.000Z',
      'created_by': 'teacher-1',
      'updated_by': 'teacher-1',
    };

    test('fromJson parses status enum from string', () {
      final attendance = Attendance.fromJson(json);
      expect(attendance.childId, 'child-1');
      expect(attendance.date, '2026-07-01');
      expect(attendance.status, AttendanceStatus.present);
      expect(attendance.createdBy, 'teacher-1');
      expect(attendance.photoPath, 'child-1/2026-07-01.jpg');
      expect(attendance.belongingsPhotoPath, 'child-1/2026-07-01-belongings.jpg');
    });

    test('fromJson leaves both photo paths null when absent', () {
      final withoutPhotos = Map<String, dynamic>.from(json)
        ..remove('photo_path')
        ..remove('belongings_photo_path');
      final attendance = Attendance.fromJson(withoutPhotos);
      expect(attendance.photoPath, isNull);
      expect(attendance.belongingsPhotoPath, isNull);
    });

    test('toJson serializes status enum as its name', () {
      final attendance = Attendance.fromJson(json);
      final out = attendance.toJson();
      expect(out['status'], 'present');
      expect(out['child_id'], 'child-1');
      expect(out['photo_path'], 'child-1/2026-07-01.jpg');
      expect(out['belongings_photo_path'], 'child-1/2026-07-01-belongings.jpg');
      expect(out.containsKey('id'), isFalse);
    });

    test('fromJson handles each AttendanceStatus value', () {
      for (final status in AttendanceStatus.values) {
        final withStatus = Map<String, dynamic>.from(json)..['status'] = status.name;
        expect(Attendance.fromJson(withStatus).status, status);
      }
    });
  });
}
