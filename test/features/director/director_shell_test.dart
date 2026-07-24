import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/services/child_service.dart';
import 'package:test_flutter/core/services/teacher_service.dart';
import 'package:test_flutter/features/director/director_shell.dart';

class MockChildService extends Mock implements ChildService {}

class MockTeacherService extends Mock implements TeacherService {}

void main() {
  testWidgets('DirectorShell renders its tabs', (tester) async {
    final mockChildren = MockChildService();
    final mockTeachers = MockTeacherService();
    when(() => mockChildren.fetchAll()).thenAnswer((_) async => []);
    when(() => mockTeachers.fetchAll()).thenAnswer((_) async => []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          childServiceProvider.overrideWithValue(mockChildren),
          teacherServiceProvider.overrideWithValue(mockTeachers),
        ],
        child: const MaterialApp(home: DirectorShell()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('People'), findsOneWidget);
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Lessons'), findsOneWidget);
    expect(find.text('Attendance'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });
}
