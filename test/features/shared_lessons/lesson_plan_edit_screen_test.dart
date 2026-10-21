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

class MockLessonPlanController extends Mock implements LessonPlanController {}

class MockSubjectController extends Mock implements SubjectController {}

class MockClassController extends Mock implements ClassController {}

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
  content: 'Watercolours',
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

  Future<void> pump(WidgetTester tester, {required Widget screen, required AppUser user}) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(user)),
          lessonPlanControllerProvider.overrideWithValue(mockPlans),
          subjectControllerProvider.overrideWithValue(mockSubjects),
          classControllerProvider.overrideWithValue(mockClasses),
        ],
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('teacher creating a plan calls createPlan', (tester) async {
    when(() => mockPlans.createPlan(
          title: any(named: 'title'),
          content: any(named: 'content'),
          subjectId: any(named: 'subjectId'),
          classId: any(named: 'classId'),
          teacherId: any(named: 'teacherId'),
          centerId: any(named: 'centerId'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => _plan(LessonPlanStatus.draft));

    await pump(tester,
        screen: const LessonPlanEditScreen(isDirector: false), user: _user('teacher'));

    // Labels sit above the fields now (not inside), so target the input by key.
    await tester.enterText(find.byKey(const Key('lesson-title')), 'Numbers');
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();

    verify(() => mockPlans.createPlan(
          title: 'Numbers',
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

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    verify(() => mockPlans.submitPlan(id: 'lp-1', actorUid: 'teacher-1')).called(1);
  });

  testWidgets('a submitted plan is read-only to its teacher (no Save)', (tester) async {
    await pump(tester,
        screen: LessonPlanEditScreen(plan: _plan(LessonPlanStatus.submitted), isDirector: false),
        user: _user('teacher'));

    // Read-only: value shown as text, no input field, no Save/Submit.
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Save draft'), findsNothing);
    expect(find.text('Submit'), findsNothing);
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

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Delete')));
    await tester.pumpAndSettle();

    verify(() => mockPlans.deletePlan('lp-1')).called(1);
  });

  testWidgets('status chip and Delete live in the app bar', (tester) async {
    await pump(tester,
        screen: LessonPlanEditScreen(plan: _plan(LessonPlanStatus.submitted), isDirector: true),
        user: _user('director'));

    final appBar = find.byType(AppBar);
    expect(find.descendant(of: appBar, matching: find.text('Awaiting approval')),
        findsOneWidget);
    expect(find.descendant(of: appBar, matching: find.byTooltip('Delete')), findsOneWidget);
  });

  testWidgets('a teacher editing a draft gets Save draft + Submit in the bottom bar',
      (tester) async {
    await pump(tester,
        screen: LessonPlanEditScreen(plan: _plan(LessonPlanStatus.draft), isDirector: false),
        user: _user('teacher'));

    expect(find.widgetWithText(OutlinedButton, 'Save draft'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Submit'), findsOneWidget);
  });

  testWidgets("the reviewer's note shows as a feedback banner", (tester) async {
    final plan = LessonPlan(
      id: 'lp-1', teacherId: 'teacher-1', centerId: 'center-1', title: 'Colours',
      content: '', status: LessonPlanStatus.rejected, reviewNote: 'Add a materials list',
      createdAt: DateTime(2026), updatedAt: DateTime(2026),
      createdBy: 'teacher-1', updatedBy: 'teacher-1',
    );
    await pump(tester,
        screen: LessonPlanEditScreen(plan: plan, isDirector: false), user: _user('teacher'));

    expect(find.text('Feedback from reviewer'), findsOneWidget);
    expect(find.text('Add a materials list'), findsOneWidget);
  });

  testWidgets('Approve uses the theme primary colour, not a hard-coded green',
      (tester) async {
    await pump(tester,
        screen: LessonPlanEditScreen(plan: _plan(LessonPlanStatus.submitted), isDirector: true),
        user: _user('director'));

    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Approve'));
    // null style = FilledButton falls back to the app theme (primary colour).
    expect(button.style, isNull);
  });

  testWidgets('fits a 360px phone with long subject/class names (no overflow)',
      (tester) async {
    when(() => mockSubjects.fetchAll()).thenAnswer((_) async => [
          Subject(id: 's1', centerId: 'center-1', name: 'Fine and gross motor skills',
              createdAt: DateTime(2026), updatedAt: DateTime(2026),
              createdBy: 'd', updatedBy: 'd'),
        ]);
    when(() => mockClasses.fetchAll()).thenAnswer((_) async => [
          ClassGroup(id: 'c1', name: 'Kindergarten Sunflowers', teacherIds: const [],
              centerId: 'center-1', createdAt: DateTime(2026),
              updatedAt: DateTime(2026), createdBy: 'd', updatedBy: 'd'),
        ]);
    final plan = LessonPlan(
      id: 'lp-1', teacherId: 'teacher-1', centerId: 'center-1', title: 'Colours',
      content: '', subjectId: 's1', classId: 'c1', status: LessonPlanStatus.submitted,
      createdAt: DateTime(2026), updatedAt: DateTime(2026),
      createdBy: 'teacher-1', updatedBy: 'teacher-1',
    );
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_user('director'))),
        lessonPlanControllerProvider.overrideWithValue(mockPlans),
        subjectControllerProvider.overrideWithValue(mockSubjects),
        classControllerProvider.overrideWithValue(mockClasses),
      ],
      child: MaterialApp(home: LessonPlanEditScreen(plan: plan, isDirector: true)),
    ));
    await tester.pumpAndSettle();

    // A RenderFlex overflow would surface here as an exception.
    expect(tester.takeException(), isNull);
    expect(find.text('Approve'), findsOneWidget);
  });
}
