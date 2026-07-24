import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/services/child_service.dart';
import 'package:test_flutter/core/services/teacher_service.dart';
import 'package:test_flutter/features/director/screens/manage_children_screen.dart';
import 'package:test_flutter/features/director/screens/manage_teachers_screen.dart';
import 'package:test_flutter/features/director/screens/people_screen.dart';

class MockChildService extends Mock implements ChildService {}

class MockTeacherService extends Mock implements TeacherService {}

void main() {
  testWidgets('shows the Teachers screen by default and switches to Children on tap',
      (tester) async {
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
        child: const MaterialApp(home: PeopleScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ManageTeachersScreen), findsOneWidget);

    await tester.tap(find.text('Children'));
    await tester.pumpAndSettle();

    expect(find.byType(ManageChildrenScreen), findsOneWidget);
  });
}
