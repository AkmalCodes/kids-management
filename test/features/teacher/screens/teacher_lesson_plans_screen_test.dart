import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/auth/auth_controller.dart';
import 'package:test_flutter/core/models/app_user.dart';
import 'package:test_flutter/core/models/lesson_plan.dart';
import 'package:test_flutter/core/controllers/class_controller.dart';
import 'package:test_flutter/core/controllers/lesson_plan_controller.dart';
import 'package:test_flutter/core/controllers/subject_controller.dart';
import 'package:test_flutter/features/shared_lessons/lesson_plan_edit_screen.dart';
import 'package:test_flutter/features/teacher/screens/teacher_lesson_plans_screen.dart';

class MockLessonPlanController extends Mock implements LessonPlanController {}

class MockSubjectController extends Mock implements SubjectController {}

class MockClassController extends Mock implements ClassController {}

AppUser _teacher() => AppUser(
  id: 'teacher-1',
  role: 'teacher',
  name: 'Ms. Smith',
  phone: '',
  centerId: 'center-1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'teacher-1',
  updatedBy: 'teacher-1',
);

LessonPlan _plan(String id, String title, LessonPlanStatus status) => LessonPlan(
  id: id,
  teacherId: 'teacher-1',
  centerId: 'center-1',
  title: title,
  content: '',
  status: status,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'teacher-1',
  updatedBy: 'teacher-1',
);

void main() {
  late MockLessonPlanController mockPlans;
  late MockSubjectController mockSubjects;
  late MockClassController mockClasses;

  setUp(() {
    mockPlans = MockLessonPlanController();
    mockSubjects = MockSubjectController();
    mockClasses = MockClassController();
    when(() => mockSubjects.fetchAll()).thenAnswer((_) async => []);
    when(() => mockClasses.fetchAll()).thenAnswer((_) async => []);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(_teacher())),
          lessonPlanControllerProvider.overrideWithValue(mockPlans),
          subjectControllerProvider.overrideWithValue(mockSubjects),
          classControllerProvider.overrideWithValue(mockClasses),
        ],
        child: const MaterialApp(home: TeacherLessonPlansScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows an empty message when there are no plans', (tester) async {
    when(() => mockPlans.fetchForTeacher('teacher-1')).thenAnswer((_) async => []);

    await pumpScreen(tester);

    expect(find.text('No lesson plans yet.'), findsOneWidget);
  });

  testWidgets('lists the teacher plans with a status chip', (tester) async {
    when(() => mockPlans.fetchForTeacher('teacher-1')).thenAnswer(
      (_) async => [_plan('lp-1', 'Colours', LessonPlanStatus.submitted)],
    );

    await pumpScreen(tester);

    expect(find.text('Colours'), findsOneWidget);
    expect(find.text('Awaiting approval'), findsOneWidget);
  });

  testWidgets('the + button opens the editor in create mode', (tester) async {
    when(() => mockPlans.fetchForTeacher('teacher-1')).thenAnswer((_) async => []);

    await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.byType(LessonPlanEditScreen), findsOneWidget);
    expect(find.text('New lesson plan'), findsOneWidget);
  });
}
