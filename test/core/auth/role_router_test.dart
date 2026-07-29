import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/auth/auth_service.dart';
import 'package:test_flutter/core/auth/role_router.dart';
import 'package:test_flutter/core/models/app_user.dart';
import 'package:test_flutter/core/services/child_service.dart';
import 'package:test_flutter/core/services/class_service.dart';
import 'package:test_flutter/core/services/teacher_service.dart';
import 'package:test_flutter/features/director/screens/manage_teachers_screen.dart';
import 'package:test_flutter/features/parent/screens/child_schedule_screen.dart';
import 'package:test_flutter/features/teacher/screens/teacher_schedule_screen.dart';

class MockChildService extends Mock implements ChildService {}

class MockTeacherService extends Mock implements TeacherService {}

class MockClassService extends Mock implements ClassService {}

AppUser _user(String role) => AppUser(
  id: 'uid-1',
  role: role,
  name: 'Test',
  phone: '',
  centerId: 'c-1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'd-1',
  updatedBy: 'd-1',
);

void main() {
  testWidgets('routes parent to ParentShell', (tester) async {
    final mockChildren = MockChildService();
    when(() => mockChildren.fetchForParent(any())).thenAnswer((_) async => []);

    await tester.pumpWidget(ProviderScope(
      // overrideWith replaces the real provider (which would hit Supabase)
      // with a fake stream — this is how we test routing logic in
      // isolation, without a real network connection. childServiceProvider
      // also needs overriding: ParentShell's first tab (ChildScheduleScreen)
      // reads it directly during build, which would otherwise crash since
      // Supabase.initialize() never runs in the test environment.
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_user('parent'))),
        childServiceProvider.overrideWithValue(mockChildren),
      ],
      child: const MaterialApp(home: RoleRouter()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ChildScheduleScreen), findsOneWidget);
  });

  testWidgets('routes teacher to TeacherShell', (tester) async {
    // TeacherShell's first tab (TeacherScheduleScreen) reads classService
    // during build to resolve the teacher's class.
    final mockClasses = MockClassService();
    when(() => mockClasses.fetchForTeacher(any())).thenAnswer((_) async => []);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_user('teacher'))),
        classServiceProvider.overrideWithValue(mockClasses),
      ],
      child: const MaterialApp(home: RoleRouter()),
    ));
    await tester.pump();
    expect(find.byType(TeacherScheduleScreen), findsOneWidget);
  });

  testWidgets('routes director to DirectorShell', (tester) async {
    final mockChildren = MockChildService();
    final mockTeachers = MockTeacherService();
    when(() => mockChildren.fetchAll()).thenAnswer((_) async => []);
    when(() => mockTeachers.fetchAll()).thenAnswer((_) async => []);

    await tester.pumpWidget(ProviderScope(
      // DirectorShell's first tab (PeopleScreen -> ManageTeachersScreen)
      // reads both services directly during build, same reasoning as the
      // parent case above.
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_user('director'))),
        childServiceProvider.overrideWithValue(mockChildren),
        teacherServiceProvider.overrideWithValue(mockTeachers),
      ],
      child: const MaterialApp(home: RoleRouter()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ManageTeachersScreen), findsOneWidget);
  });
}
