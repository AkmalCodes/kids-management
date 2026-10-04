import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kids_management/core/controllers/child_controller.dart';
import 'package:kids_management/core/controllers/notification_controller.dart';
import 'package:kids_management/core/controllers/teacher_controller.dart';
import 'package:kids_management/features/director/director_shell.dart';

class MockChildController extends Mock implements ChildController {}

class MockTeacherController extends Mock implements TeacherController {}

void main() {
  testWidgets('DirectorShell renders its tabs', (tester) async {
    final mockChildren = MockChildController();
    final mockTeachers = MockTeacherController();
    when(() => mockChildren.fetchAll()).thenAnswer((_) async => []);
    when(() => mockTeachers.fetchAll()).thenAnswer((_) async => []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          childControllerProvider.overrideWithValue(mockChildren),
          teacherControllerProvider.overrideWithValue(mockTeachers),
          // The AppBar's NotificationBellAction watches this; without an
          // override it would reach for the real (uninitialised) Supabase client.
          notificationsProvider.overrideWith((ref) => Stream.value([])),
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
