import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kids_management/core/models/app_notification.dart';
import 'package:kids_management/core/models/lesson_plan.dart';
import 'package:kids_management/core/controllers/class_controller.dart';
import 'package:kids_management/core/controllers/lesson_plan_controller.dart';
import 'package:kids_management/core/controllers/notification_controller.dart';
import 'package:kids_management/core/controllers/subject_controller.dart';
import 'package:kids_management/features/shared_lessons/lesson_plan_edit_screen.dart';
import 'package:kids_management/shared/screens/notifications_screen.dart';

class MockNotificationController extends Mock implements NotificationController {}

class MockLessonPlanController extends Mock implements LessonPlanController {}

// LessonPlanEditScreen loads subjects + classes in initState, so the
// tap-through test needs these mocked too or it would hit real Supabase.
class MockSubjectController extends Mock implements SubjectController {}

class MockClassController extends Mock implements ClassController {}

AppNotification _notification({required bool read}) => AppNotification(
      id: 'n-1',
      userId: 'director-1',
      type: 'lesson_plan',
      status: 'SUBMITTED',
      title: 'Lesson plan submitted',
      body: 'Ms. Smith submitted "Colours" for review',
      entityId: 'lp-1',
      readAt: read ? DateTime(2026, 9, 15) : null,
      createdAt: DateTime(2026, 9, 15),
    );

LessonPlan _plan() => LessonPlan(
      id: 'lp-1',
      teacherId: 'teacher-1',
      centerId: 'center-1',
      title: 'Colours',
      content: 'Watercolours',
      status: LessonPlanStatus.submitted,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      createdBy: 'teacher-1',
      updatedBy: 'teacher-1',
    );

void main() {
  late MockNotificationController mockNotifications;
  late MockLessonPlanController mockPlans;
  late MockSubjectController mockSubjects;
  late MockClassController mockClasses;

  setUp(() {
    mockNotifications = MockNotificationController();
    mockPlans = MockLessonPlanController();
    mockSubjects = MockSubjectController();
    mockClasses = MockClassController();
    when(() => mockSubjects.fetchAll()).thenAnswer((_) async => []);
    when(() => mockClasses.fetchAll()).thenAnswer((_) async => []);
  });

  Future<void> pumpScreen(WidgetTester tester, List<AppNotification> data) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationsProvider.overrideWith((ref) => Stream.value(data)),
          notificationControllerProvider.overrideWithValue(mockNotifications),
          lessonPlanControllerProvider.overrideWithValue(mockPlans),
          subjectControllerProvider.overrideWithValue(mockSubjects),
          classControllerProvider.overrideWithValue(mockClasses),
        ],
        child: const MaterialApp(home: NotificationsScreen(isDirector: true)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows an empty message when there are no notifications', (tester) async {
    await pumpScreen(tester, []);
    expect(find.text('No notifications yet.'), findsOneWidget);
  });

  testWidgets('lists a notification title and body', (tester) async {
    await pumpScreen(tester, [_notification(read: false)]);
    expect(find.text('Lesson plan submitted'), findsOneWidget);
    expect(find.text('Ms. Smith submitted "Colours" for review'), findsOneWidget);
  });

  testWidgets('tapping a row marks it read and opens the plan editor', (tester) async {
    when(() => mockNotifications.markRead('n-1')).thenAnswer((_) async {});
    when(() => mockPlans.getPlan('lp-1')).thenAnswer((_) async => _plan());

    await pumpScreen(tester, [_notification(read: false)]);
    await tester.tap(find.text('Lesson plan submitted'));
    await tester.pumpAndSettle();

    verify(() => mockNotifications.markRead('n-1')).called(1);
    expect(find.byType(LessonPlanEditScreen), findsOneWidget);
  });

  testWidgets('shows a snackbar when the plan no longer exists', (tester) async {
    when(() => mockNotifications.markRead('n-1')).thenAnswer((_) async {});
    when(() => mockPlans.getPlan('lp-1')).thenAnswer((_) async => null);

    await pumpScreen(tester, [_notification(read: false)]);
    await tester.tap(find.text('Lesson plan submitted'));
    await tester.pumpAndSettle();

    expect(find.text('That lesson plan no longer exists.'), findsOneWidget);
    expect(find.byType(LessonPlanEditScreen), findsNothing);
  });
}
