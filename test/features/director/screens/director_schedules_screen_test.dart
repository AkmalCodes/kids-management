import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/models/app_user.dart';
import 'package:test_flutter/core/models/child.dart';
import 'package:test_flutter/core/services/child_service.dart';
import 'package:test_flutter/core/services/teacher_service.dart';
import 'package:test_flutter/features/director/screens/director_schedules_screen.dart';
import 'package:test_flutter/features/director/screens/person_schedule_screen.dart';

class MockTeacherService extends Mock implements TeacherService {}

class MockChildService extends Mock implements ChildService {}

AppUser _teacher(String id, String name) => AppUser(
  id: id,
  role: 'teacher',
  name: name,
  phone: '',
  centerId: 'center-1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

Child _child(String id, String name) => Child(
  id: id,
  name: name,
  dob: DateTime(2022, 1, 1),
  centerId: 'center-1',
  roomId: '',
  teacherId: 'teacher-1',
  allergies: '',
  notes: '',
  enrolledAt: DateTime(2026),
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

void main() {
  late MockTeacherService mockTeachers;
  late MockChildService mockChildren;

  setUp(() {
    mockTeachers = MockTeacherService();
    mockChildren = MockChildService();
  });

  Future<void> pumpScreen(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          overrides: [
            teacherServiceProvider.overrideWithValue(mockTeachers),
            childServiceProvider.overrideWithValue(mockChildren),
          ],
          child: const MaterialApp(
            home: Scaffold(body: DirectorSchedulesScreen()),
          ),
        ),
      );

  testWidgets('shows Teachers tab by default with all teachers listed', (tester) async {
    when(() => mockTeachers.fetchAll())
        .thenAnswer((_) async => [_teacher('teacher-1', 'Ms. Smith')]);
    when(() => mockChildren.fetchAll()).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Ms. Smith'), findsOneWidget);
  });

  testWidgets('switching to the Children tab shows all children', (tester) async {
    when(() => mockTeachers.fetchAll()).thenAnswer((_) async => []);
    when(() => mockChildren.fetchAll()).thenAnswer((_) async => [_child('child-1', 'Alice')]);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Children'));
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('tapping a teacher opens their PersonScheduleScreen', (tester) async {
    when(() => mockTeachers.fetchAll())
        .thenAnswer((_) async => [_teacher('teacher-1', 'Ms. Smith')]);
    when(() => mockChildren.fetchAll()).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ms. Smith'));
    await tester.pumpAndSettle();

    final screen = tester.widget<PersonScheduleScreen>(find.byType(PersonScheduleScreen));
    expect(screen.title, 'Ms. Smith');
    expect(screen.type, 'teacher');
    expect(screen.refId, 'teacher-1');
    expect(screen.centerId, 'center-1');
  });

  testWidgets('tapping a child opens their PersonScheduleScreen', (tester) async {
    when(() => mockTeachers.fetchAll()).thenAnswer((_) async => []);
    when(() => mockChildren.fetchAll()).thenAnswer((_) async => [_child('child-1', 'Alice')]);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Children'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    final screen = tester.widget<PersonScheduleScreen>(find.byType(PersonScheduleScreen));
    expect(screen.title, 'Alice');
    expect(screen.type, 'child');
    expect(screen.refId, 'child-1');
    expect(screen.centerId, 'center-1');
  });
}
