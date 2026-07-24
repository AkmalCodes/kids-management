import 'package:flutter_test/flutter_test.dart';
import 'package:test_flutter/core/models/child.dart';

void main() {
  final sampleJson = {
    'id': 'child-1',
    'name': 'Alice',
    'dob': '2022-06-01',
    'center_id': 'center-1',
    'room_id': 'Room A',
    'teacher_id': 'teacher-1',
    'allergies': 'Peanuts',
    'notes': 'n/a',
    'height_cm': 95.5,
    'enrolled_at': '2026-01-01',
    'created_at': '2026-01-01T00:00:00.000Z',
    'updated_at': '2026-01-01T00:00:00.000Z',
    'created_by': 'director-1',
    'updated_by': 'director-1',
  };

  test('fromJson parses height_cm', () {
    final child = Child.fromJson(sampleJson);
    expect(child.heightCm, 95.5);
  });

  test('heightCm is null when absent', () {
    final json = Map<String, dynamic>.from(sampleJson)..remove('height_cm');
    expect(Child.fromJson(json).heightCm, isNull);
  });

  test('fromJson coerces an integer height to double', () {
    final json = Map<String, dynamic>.from(sampleJson)..['height_cm'] = 100;
    expect(Child.fromJson(json).heightCm, 100.0);
  });

  test('toJson includes height_cm', () {
    final child = Child.fromJson(sampleJson);
    expect(child.toJson()['height_cm'], 95.5);
  });

  test('copyWith updates only the given fields', () {
    final child = Child.fromJson(sampleJson);
    final updated = child.copyWith(name: 'Alice B', heightCm: 101);

    expect(updated.name, 'Alice B');
    expect(updated.heightCm, 101);
    expect(updated.allergies, 'Peanuts'); // unchanged
    expect(updated.id, 'child-1');
  });

  test('copyWith can clear teacher and height', () {
    final child = Child.fromJson(sampleJson);
    final updated = child.copyWith(clearTeacherId: true, clearHeight: true);

    expect(updated.teacherId, isNull);
    expect(updated.heightCm, isNull);
  });
}
