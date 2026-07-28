import 'package:flutter_test/flutter_test.dart';
import 'package:test_flutter/core/models/daily_report.dart';

void main() {
  final sampleJson = {
    'id': 'report-1',
    'child_id': 'child-1',
    'teacher_id': 'teacher-1',
    'center_id': 'center-1',
    'date': '2026-07-28',
    'text': 'Had a great day painting.',
    'image_paths': ['child-1/2026-07-28/1.jpg', 'child-1/2026-07-28/2.jpg'],
    'created_at': '2026-07-28T00:00:00.000Z',
    'updated_at': '2026-07-28T00:00:00.000Z',
    'created_by': 'teacher-1',
    'updated_by': 'teacher-1',
  };

  test('fromJson parses all fields including image_paths', () {
    final report = DailyReport.fromJson(sampleJson);
    expect(report.id, 'report-1');
    expect(report.childId, 'child-1');
    expect(report.date, '2026-07-28');
    expect(report.text, 'Had a great day painting.');
    expect(report.imagePaths, ['child-1/2026-07-28/1.jpg', 'child-1/2026-07-28/2.jpg']);
  });

  test('imagePaths defaults to empty when null/absent', () {
    final json = Map<String, dynamic>.from(sampleJson)..remove('image_paths');
    expect(DailyReport.fromJson(json).imagePaths, isEmpty);
  });

  test('toJson serializes image_paths and omits id', () {
    final report = DailyReport.fromJson(sampleJson);
    final json = report.toJson();
    expect(json['image_paths'], ['child-1/2026-07-28/1.jpg', 'child-1/2026-07-28/2.jpg']);
    expect(json['text'], 'Had a great day painting.');
    expect(json.containsKey('id'), isFalse);
  });
}
