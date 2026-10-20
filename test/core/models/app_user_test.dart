import 'package:flutter_test/flutter_test.dart';
import 'package:kawankecil/core/models/app_user.dart';

void main() {
  group('AppUser', () {
    final sampleJson = {
      'id': 'uid-1',
      'role': 'teacher',
      'name': 'Alice',
      'phone': '0123456789',
      'center_id': 'center-1',
      'created_at': '2026-07-01T00:00:00.000Z',
      'updated_at': '2026-07-01T00:00:00.000Z',
      'created_by': 'director-1',
      'updated_by': 'director-1',
    };

    test('fromJson parses all fields', () {
      final user = AppUser.fromJson(sampleJson);

      expect(user.id, 'uid-1');
      expect(user.role, 'teacher');
      expect(user.name, 'Alice');
      expect(user.phone, '0123456789');
      expect(user.centerId, 'center-1');
      expect(user.createdBy, 'director-1');
      expect(user.updatedBy, 'director-1');
    });

    test('toJson serializes all fields except id', () {
      final user = AppUser.fromJson(sampleJson);
      final json = user.toJson();

      expect(json['role'], 'teacher');
      expect(json['name'], 'Alice');
      expect(json['created_by'], 'director-1');
      expect(json.containsKey('id'), isFalse); // id is the PK, not sent in body
    });

    test('fromJson handles null phone gracefully', () {
      final json = Map<String, dynamic>.from(sampleJson);
      json['phone'] = null;
      final user = AppUser.fromJson(json);
      expect(user.phone, '');
    });

    test('mustSetPassword defaults to false when absent', () {
      final user = AppUser.fromJson(sampleJson);
      expect(user.mustSetPassword, isFalse);
    });

    test('fromJson parses must_set_password when present', () {
      final json = Map<String, dynamic>.from(sampleJson);
      json['must_set_password'] = true;
      final user = AppUser.fromJson(json);
      expect(user.mustSetPassword, isTrue);
    });
  });
}
