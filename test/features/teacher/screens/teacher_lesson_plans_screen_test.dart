import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kawankecil/core/auth/auth_controller.dart';
import 'package:kawankecil/core/models/app_user.dart';
import 'package:kawankecil/core/models/class_group.dart';
import 'package:kawankecil/core/models/lesson_plan.dart';
import 'package:kawankecil/core/models/subject.dart';
import 'package:kawankecil/core/controllers/class_controller.dart';
import 'package:kawankecil/core/controllers/lesson_plan_controller.dart';
import 'package:kawankecil/core/controllers/subject_controller.dart';
import 'package:kawankecil/features/shared_lessons/lesson_plan_edit_screen.dart';
import 'package:kawankecil/features/teacher/screens/teacher_lesson_plans_screen.dart';

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

LessonPlan _plan(String id, String title, LessonPlanStatus status,
        {String? subjectId, String? classId, String? note}) =>
    LessonPlan(
  id: id,
  subjectId: subjectId,
  classId: classId,
  reviewNote: note,
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

  testWidgets('Create lesson plan opens the editor in create mode', (tester) async {
    when(() => mockPlans.fetchForTeacher('teacher-1')).thenAnswer((_) async => []);

    await pumpScreen(tester);

    await tester.tap(find.text('Create lesson plan'));
    await tester.pumpAndSettle();

    expect(find.byType(LessonPlanEditScreen), findsOneWidget);
    expect(find.text('New lesson plan'), findsOneWidget);
  });

  testWidgets('pulling down refetches the plans (page is kept alive between tabs)',
      (tester) async {
    when(() => mockPlans.fetchForTeacher('teacher-1')).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.fling(find.text('No lesson plans yet.'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    verify(() => mockPlans.fetchForTeacher('teacher-1')).called(2);
  });

  testWidgets('greets the teacher by name', (tester) async {
    when(() => mockPlans.fetchForTeacher('teacher-1')).thenAnswer((_) async => []);

    await pumpScreen(tester);

    expect(find.textContaining('Ms. Smith'), findsOneWidget);
  });

  testWidgets('summary cards count plans, ones needing attention, and approved',
      (tester) async {
    when(() => mockPlans.fetchForTeacher('teacher-1')).thenAnswer((_) async => [
          _plan('1', 'A', LessonPlanStatus.draft),
          _plan('2', 'B', LessonPlanStatus.rejected),
          _plan('3', 'C', LessonPlanStatus.approved),
          _plan('4', 'D', LessonPlanStatus.approved),
          _plan('5', 'E', LessonPlanStatus.approved),
        ]);

    await pumpScreen(tester);

    expect(find.text('5'), findsOneWidget); // total
    expect(find.text('2 need attention'), findsOneWidget); // draft + rejected
    expect(find.text('3'), findsOneWidget); // approved
    expect(find.text('Ready to teach'), findsOneWidget);
  });

  testWidgets('a card shows subject and class names, and no date', (tester) async {
    when(() => mockSubjects.fetchAll()).thenAnswer((_) async => [
          Subject(id: 's1', centerId: 'center-1', name: 'Arts',
              createdAt: DateTime(2026), updatedAt: DateTime(2026),
              createdBy: 'd', updatedBy: 'd'),
        ]);
    when(() => mockClasses.fetchAll()).thenAnswer((_) async => [
          ClassGroup(id: 'c1', name: 'Class A', teacherIds: const [],
              centerId: 'center-1', createdAt: DateTime(2026),
              updatedAt: DateTime(2026), createdBy: 'd', updatedBy: 'd'),
        ]);
    when(() => mockPlans.fetchForTeacher('teacher-1')).thenAnswer((_) async =>
        [_plan('1', 'Colours', LessonPlanStatus.draft, subjectId: 's1', classId: 'c1')]);

    await pumpScreen(tester);

    expect(find.text('Arts · Class A'), findsOneWidget);
  });

  testWidgets('a rejected plan shows the reviewer feedback with an Edit shortcut',
      (tester) async {
    when(() => mockPlans.fetchForTeacher('teacher-1')).thenAnswer((_) async => [
          _plan('1', 'Colours', LessonPlanStatus.rejected, note: 'Add a materials list'),
        ]);

    await pumpScreen(tester);

    expect(find.text('Needs changes'), findsOneWidget);
    expect(find.textContaining('Add a materials list'), findsOneWidget);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.byType(LessonPlanEditScreen), findsOneWidget);
  });
}
