import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kids_management/core/controllers/child_controller.dart';
import 'package:kids_management/core/controllers/teacher_controller.dart';
import 'package:kids_management/features/director/screens/manage_children_screen.dart';
import 'package:kids_management/features/director/screens/manage_teachers_screen.dart';
import 'package:kids_management/features/director/screens/people_screen.dart';

class MockChildController extends Mock implements ChildController {}

class MockTeacherController extends Mock implements TeacherController {}

void main() {
  testWidgets('shows the Teachers screen by default and switches to Children on tap',
      (tester) async {
    final mockChildren = MockChildController();
    final mockTeachers = MockTeacherController();
    when(() => mockChildren.fetchAll()).thenAnswer((_) async => []);
    when(() => mockTeachers.fetchAll()).thenAnswer((_) async => []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          childControllerProvider.overrideWithValue(mockChildren),
          teacherControllerProvider.overrideWithValue(mockTeachers),
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
