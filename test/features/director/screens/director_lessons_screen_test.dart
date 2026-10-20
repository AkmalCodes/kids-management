import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kawankecil/core/auth/auth_controller.dart';
import 'package:kawankecil/core/models/app_user.dart';
import 'package:kawankecil/core/models/lesson_plan.dart';
import 'package:kawankecil/core/controllers/class_controller.dart';
import 'package:kawankecil/core/controllers/lesson_plan_controller.dart';
import 'package:kawankecil/core/controllers/subject_controller.dart';
import 'package:kawankecil/core/controllers/teacher_controller.dart';
import 'package:kawankecil/features/director/screens/director_lessons_screen.dart';
import 'package:kawankecil/features/director/screens/manage_subjects_screen.dart';
import 'package:kawankecil/features/shared_lessons/lesson_plan_edit_screen.dart';
import 'package:kawankecil/shared/widgets/lesson_plan_status_chip.dart';

class MockLessonPlanController extends Mock implements LessonPlanController {}

class MockSubjectController extends Mock implements SubjectController {}

class MockTeacherController extends Mock implements TeacherController {}

class MockClassController extends Mock implements ClassController {}

AppUser _director() => AppUser(
  id: 'director-1',
  role: 'director',
  name: 'Director',
  phone: '',
  centerId: 'center-1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

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

LessonPlan _plan(String id, String title, String teacherId, LessonPlanStatus status) => LessonPlan(
  id: id,
  teacherId: teacherId,
  centerId: 'center-1',
  title: title,
  content: '',
  status: status,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: teacherId,
  updatedBy: teacherId,
);

void main() {
  late MockLessonPlanController mockPlans;
  late MockSubjectController mockSubjects;
  late MockTeacherController mockTeachers;
  late MockClassController mockClasses;

  setUp(() {
    mockPlans = MockLessonPlanController();
    mockSubjects = MockSubjectController();
    mockTeachers = MockTeacherController();
    mockClasses = MockClassController();
    when(() => mockSubjects.fetchAll()).thenAnswer((_) async => []);
    when(() => mockClasses.fetchAll()).thenAnswer((_) async => []);
    when(() => mockTeachers.fetchAll())
        .thenAnswer((_) async => [_teacher('teacher-1', 'Ms. Smith')]);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    // Tall surface so the pushed editor's Approve/Reject buttons are built
    // (a ListView only lays out what's in the viewport).
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(_director())),
          lessonPlanControllerProvider.overrideWithValue(mockPlans),
          subjectControllerProvider.overrideWithValue(mockSubjects),
          teacherControllerProvider.overrideWithValue(mockTeachers),
          classControllerProvider.overrideWithValue(mockClasses),
        ],
        child: const MaterialApp(home: Scaffold(body: DirectorLessonsScreen())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists all plans with the teacher name and status', (tester) async {
    when(() => mockPlans.fetchAll()).thenAnswer(
      (_) async => [_plan('lp-1', 'Colours', 'teacher-1', LessonPlanStatus.submitted)],
    );

    await pumpScreen(tester);

    expect(find.text('Colours'), findsOneWidget);
    expect(find.textContaining('Ms. Smith'), findsOneWidget);
    // The row's status chip (the filter dropdown also shows this label now).
    expect(
      find.descendant(
          of: find.byType(LessonPlanStatusChip), matching: find.text('Awaiting approval')),
      findsOneWidget,
    );
  });

  testWidgets('tapping a plan opens the editor as director', (tester) async {
    when(() => mockPlans.fetchAll()).thenAnswer(
      (_) async => [_plan('lp-1', 'Colours', 'teacher-1', LessonPlanStatus.submitted)],
    );

    await pumpScreen(tester);
    await tester.tap(find.text('Colours'));
    await tester.pumpAndSettle();

    expect(find.byType(LessonPlanEditScreen), findsOneWidget);
    // Director sees the review actions on a submitted plan.
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
  });

  testWidgets('the Subjects button opens subject management', (tester) async {
    when(() => mockPlans.fetchAll()).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.tap(find.text('Subjects'));
    await tester.pumpAndSettle();

    expect(find.byType(ManageSubjectsScreen), findsOneWidget);
  });
}
