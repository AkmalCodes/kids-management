import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kids_management/core/auth/auth_controller.dart';
import 'package:kids_management/core/auth/role_router.dart';
import 'package:kids_management/core/models/app_user.dart';
import 'package:kids_management/core/controllers/child_controller.dart';
import 'package:kids_management/core/controllers/class_controller.dart';
import 'package:kids_management/core/controllers/notification_controller.dart';
import 'package:kids_management/core/controllers/teacher_controller.dart';
import 'package:kids_management/features/director/screens/manage_teachers_screen.dart';
import 'package:kids_management/features/parent/screens/child_schedule_screen.dart';
import 'package:kids_management/features/teacher/screens/teacher_schedule_screen.dart';

class MockChildController extends Mock implements ChildController {}

class MockTeacherController extends Mock implements TeacherController {}

class MockClassController extends Mock implements ClassController {}

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
    final mockChildren = MockChildController();
    when(() => mockChildren.fetchForParent(any())).thenAnswer((_) async => []);

    await tester.pumpWidget(ProviderScope(
      // overrideWith replaces the real provider (which would hit Supabase)
      // with a fake stream — this is how we test routing logic in
      // isolation, without a real network connection. childControllerProvider
      // also needs overriding: ParentShell's first tab (ChildScheduleScreen)
      // reads it directly during build, which would otherwise crash since
      // Supabase.initialize() never runs in the test environment.
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_user('parent'))),
        childControllerProvider.overrideWithValue(mockChildren),
      ],
      child: const MaterialApp(home: RoleRouter()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ChildScheduleScreen), findsOneWidget);
  });

  testWidgets('routes teacher to TeacherShell', (tester) async {
    // TeacherShell's first tab (TeacherScheduleScreen) reads classService
    // during build to resolve the teacher's class.
    final mockClasses = MockClassController();
    when(() => mockClasses.fetchForTeacher(any())).thenAnswer((_) async => []);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_user('teacher'))),
        classControllerProvider.overrideWithValue(mockClasses),
        // The AppBar's NotificationBellAction watches this; without an
        // override it would reach for the real (uninitialised) Supabase client.
        notificationsProvider.overrideWith((ref) => Stream.value([])),
      ],
      child: const MaterialApp(home: RoleRouter()),
    ));
    await tester.pump();
    expect(find.byType(TeacherScheduleScreen), findsOneWidget);
  });

  testWidgets('routes director to DirectorShell', (tester) async {
    final mockChildren = MockChildController();
    final mockTeachers = MockTeacherController();
    when(() => mockChildren.fetchAll()).thenAnswer((_) async => []);
    when(() => mockTeachers.fetchAll()).thenAnswer((_) async => []);

    await tester.pumpWidget(ProviderScope(
      // DirectorShell's first tab (PeopleScreen -> ManageTeachersScreen)
      // reads both services directly during build, same reasoning as the
      // parent case above.
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_user('director'))),
        childControllerProvider.overrideWithValue(mockChildren),
        teacherControllerProvider.overrideWithValue(mockTeachers),
        // The AppBar's NotificationBellAction watches this; without an
        // override it would reach for the real (uninitialised) Supabase client.
        notificationsProvider.overrideWith((ref) => Stream.value([])),
      ],
      child: const MaterialApp(home: RoleRouter()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ManageTeachersScreen), findsOneWidget);
  });
}
