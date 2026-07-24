import 'package:flutter_test/flutter_test.dart';
import 'package:test_flutter/core/models/child.dart';

void main() {
  final sampleJson = {
    'id': 'child-1',
    'name': 'Alice',
    'dob': '2022-06-01',
    'center_id': 'center-1',
    'class_name': 'Class A',
    'teacher_id': 'teacher-1',
    'allergies': 'Peanuts',
    'notes': 'n/a',
    'enrolled_at': '2026-01-01',
    'created_at': '2026-01-01T00:00:00.000Z',
    'updated_at': '2026-01-01T00:00:00.000Z',
    'created_by': 'director-1',
    'updated_by': 'director-1',
  };

  test('copyWith updates only the given fields', () {
    final child = Child.fromJson(sampleJson);
    final updated = child.copyWith(name: 'Alice B', className: 'Class B');

    expect(updated.name, 'Alice B');
    expect(updated.className, 'Class B');
    expect(updated.allergies, 'Peanuts'); // unchanged
    expect(updated.id, 'child-1');
  });

  test('copyWith can clear the teacher', () {
    final child = Child.fromJson(sampleJson);
    final updated = child.copyWith(clearTeacherId: true);

    expect(updated.teacherId, isNull);
  });
}
