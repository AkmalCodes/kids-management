import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/core/models/class_group.dart';

void main() {
  group('ClassGroup.fromJson', () {
    Map<String, dynamic> row({Object? teacherUids = const <String>[]}) => {
      'id': 'class-1',
      'name': 'Sunflowers',
      'teacher_uids': teacherUids,
      'center_id': 'center-1',
      'avatar_path': null,
      'created_at': '2026-09-04T00:00:00.000Z',
      'updated_at': '2026-09-04T00:00:00.000Z',
      'created_by': 'director-1',
      'updated_by': 'director-1',
    };

    test('parses a multi-element teacher_uids array', () {
      final c = ClassGroup.fromJson(row(teacherUids: ['t-1', 't-2']));
      expect(c.teacherIds, ['t-1', 't-2']);
    });

    test('an empty array gives an empty list', () {
      expect(ClassGroup.fromJson(row(teacherUids: <String>[])).teacherIds, isEmpty);
    });

    test('a null or missing teacher_uids gives an empty list', () {
      expect(ClassGroup.fromJson(row(teacherUids: null)).teacherIds, isEmpty);
      final noKey = row()..remove('teacher_uids');
      expect(ClassGroup.fromJson(noKey).teacherIds, isEmpty);
    });
  });
}
