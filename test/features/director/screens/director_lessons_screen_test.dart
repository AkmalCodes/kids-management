import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/auth/auth_service.dart';
import 'package:test_flutter/core/models/app_user.dart';
import 'package:test_flutter/core/models/lesson_plan.dart';
import 'package:test_flutter/core/services/class_service.dart';
import 'package:test_flutter/core/services/lesson_plan_service.dart';
import 'package:test_flutter/core/services/subject_service.dart';
import 'package:test_flutter/core/services/teacher_service.dart';
import 'package:test_flutter/features/director/screens/director_lessons_screen.dart';
import 'package:test_flutter/features/director/screens/manage_subjects_screen.dart';
import 'package:test_flutter/features/shared_lessons/lesson_plan_edit_screen.dart';
import 'package:test_flutter/shared/widgets/lesson_plan_status_chip.dart';

class MockLessonPlanService extends Mock implements LessonPlanService {}

class MockSubjectService extends Mock implements SubjectService {}

class MockTeacherService extends Mock implements TeacherService {}

class MockClassService extends Mock implements ClassService {}

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
  late MockLessonPlanService mockPlans;
  late MockSubjectService mockSubjects;
  late MockTeacherService mockTeachers;
  late MockClassService mockClasses;

  setUp(() {
    mockPlans = MockLessonPlanService();
    mockSubjects = MockSubjectService();
    mockTeachers = MockTeacherService();
    mockClasses = MockClassService();
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
          lessonPlanServiceProvider.overrideWithValue(mockPlans),
          subjectServiceProvider.overrideWithValue(mockSubjects),
          teacherServiceProvider.overrideWithValue(mockTeachers),
          classServiceProvider.overrideWithValue(mockClasses),
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
