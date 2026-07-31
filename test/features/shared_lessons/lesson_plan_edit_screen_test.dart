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
import 'package:test_flutter/features/shared_lessons/lesson_plan_edit_screen.dart';

class MockLessonPlanService extends Mock implements LessonPlanService {}

class MockSubjectService extends Mock implements SubjectService {}

class MockClassService extends Mock implements ClassService {}

AppUser _user(String role) => AppUser(
  id: '$role-1',
  role: role,
  name: role,
  phone: '',
  centerId: 'center-1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: '$role-1',
  updatedBy: '$role-1',
);

LessonPlan _plan(LessonPlanStatus status) => LessonPlan(
  id: 'lp-1',
  teacherId: 'teacher-1',
  centerId: 'center-1',
  title: 'Colours',
  date: '2026-08-03',
  content: 'Watercolours',
  status: status,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'teacher-1',
  updatedBy: 'teacher-1',
);

void main() {
  late MockLessonPlanService mockPlans;
  late MockSubjectService mockSubjects;
  late MockClassService mockClasses;

  setUp(() {
    mockPlans = MockLessonPlanService();
    mockSubjects = MockSubjectService();
    mockClasses = MockClassService();
    when(() => mockSubjects.fetchAll()).thenAnswer((_) async => []);
    when(() => mockClasses.fetchAll()).thenAnswer((_) async => []);
  });

  Future<void> pump(WidgetTester tester, {required Widget screen, required AppUser user}) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(user)),
          lessonPlanServiceProvider.overrideWithValue(mockPlans),
          subjectServiceProvider.overrideWithValue(mockSubjects),
          classServiceProvider.overrideWithValue(mockClasses),
        ],
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('teacher creating a plan calls createPlan', (tester) async {
    when(() => mockPlans.createPlan(
          title: any(named: 'title'),
          date: any(named: 'date'),
          content: any(named: 'content'),
          subjectId: any(named: 'subjectId'),
          classId: any(named: 'classId'),
          teacherId: any(named: 'teacherId'),
          centerId: any(named: 'centerId'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => _plan(LessonPlanStatus.draft));

    await pump(tester,
        screen: const LessonPlanEditScreen(isDirector: false), user: _user('teacher'));

    // Title + Content are both empty inputs in create mode; target by label.
    await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Numbers');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verify(() => mockPlans.createPlan(
          title: 'Numbers',
          date: any(named: 'date'),
          content: any(named: 'content'),
          subjectId: null,
          classId: null,
          teacherId: 'teacher-1',
          centerId: 'center-1',
          actorUid: 'teacher-1',
        )).called(1);
  });

  testWidgets('teacher submitting saves then flips status to submitted', (tester) async {
    when(() => mockPlans.updatePlan(
          id: any(named: 'id'),
          title: any(named: 'title'),
          date: any(named: 'date'),
          content: any(named: 'content'),
          subjectId: any(named: 'subjectId'),
          classId: any(named: 'classId'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => _plan(LessonPlanStatus.draft));
    when(() => mockPlans.submitPlan(id: any(named: 'id'), actorUid: any(named: 'actorUid')))
        .thenAnswer((_) async => _plan(LessonPlanStatus.submitted));

    await pump(tester,
        screen: LessonPlanEditScreen(plan: _plan(LessonPlanStatus.draft), isDirector: false),
        user: _user('teacher'));

    await tester.tap(find.text('Submit for approval'));
    await tester.pumpAndSettle();

    verify(() => mockPlans.submitPlan(id: 'lp-1', actorUid: 'teacher-1')).called(1);
  });

  testWidgets('a submitted plan is read-only to its teacher (no Save)', (tester) async {
    await pump(tester,
        screen: LessonPlanEditScreen(plan: _plan(LessonPlanStatus.submitted), isDirector: false),
        user: _user('teacher'));

    // Read-only: value shown as text, no input field, no Save/Submit.
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Save'), findsNothing);
    expect(find.text('Submit for approval'), findsNothing);
    expect(find.text('Colours'), findsWidgets);
  });

  testWidgets('director approving a submitted plan calls reviewPlan(approved)',
      (tester) async {
    when(() => mockPlans.reviewPlan(
          id: any(named: 'id'),
          approved: any(named: 'approved'),
          note: any(named: 'note'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => _plan(LessonPlanStatus.approved));

    await pump(tester,
        screen: LessonPlanEditScreen(plan: _plan(LessonPlanStatus.submitted), isDirector: true),
        user: _user('director'));

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    // Confirm in the dialog.
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Approve')));
    await tester.pumpAndSettle();

    verify(() => mockPlans.reviewPlan(
          id: 'lp-1',
          approved: true,
          note: any(named: 'note'),
          actorUid: 'director-1',
        )).called(1);
  });

  testWidgets('deleting a plan confirms then calls deletePlan', (tester) async {
    when(() => mockPlans.deletePlan(any())).thenAnswer((_) async {});

    await pump(tester,
        screen: LessonPlanEditScreen(plan: _plan(LessonPlanStatus.draft), isDirector: false),
        user: _user('teacher'));

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Delete')));
    await tester.pumpAndSettle();

    verify(() => mockPlans.deletePlan('lp-1')).called(1);
  });
}
