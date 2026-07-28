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
    'class_id': 'class-1',
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

  test('parses class_id and round-trips it through toJson', () {
    final child = Child.fromJson(sampleJson);
    expect(child.classId, 'class-1');
    expect(child.toJson()['class_id'], 'class-1');
  });

  test('classId is null when absent, and copyWith preserves/clears it', () {
    final json = Map<String, dynamic>.from(sampleJson)..remove('class_id');
    final child = Child.fromJson(json);
    expect(child.classId, isNull);

    final withClass = Child.fromJson(sampleJson);
    // Not passing classId preserves it; clearClassId nulls it.
    expect(withClass.copyWith(name: 'X').classId, 'class-1');
    expect(withClass.copyWith(clearClassId: true).classId, isNull);
  });
}
