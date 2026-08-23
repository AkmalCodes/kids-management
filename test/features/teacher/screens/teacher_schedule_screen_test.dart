import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kids_management/core/auth/auth_controller.dart';
import 'package:kids_management/core/models/app_user.dart';
import 'package:kids_management/core/models/class_group.dart';
import 'package:kids_management/core/models/schedule.dart';
import 'package:kids_management/core/controllers/class_controller.dart';
import 'package:kids_management/core/controllers/schedule_controller.dart';
import 'package:kids_management/features/teacher/screens/teacher_schedule_screen.dart';

class MockClassController extends Mock implements ClassController {}

AppUser _teacher() => AppUser(
  id: 'teacher-1',
  role: 'teacher',
  name: 'Teacher',
  phone: '',
  centerId: 'center-1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

ClassGroup _classGroup() => ClassGroup(
  id: 'class-1',
  name: 'Sunflowers',
  teacherId: 'teacher-1',
  centerId: 'center-1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

void main() {
  late MockClassController mockClasses;

  setUp(() {
    mockClasses = MockClassController();
  });

  Future<void> pumpScreen(WidgetTester tester, {List<Override> extra = const []}) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => Stream.value(_teacher())),
            classControllerProvider.overrideWithValue(mockClasses),
            ...extra,
          ],
          child: const MaterialApp(home: Scaffold(body: TeacherScheduleScreen())),
        ),
      );

  testWidgets('prompts when the teacher has no class', (tester) async {
    when(() => mockClasses.fetchForTeacher('teacher-1')).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text("You're not assigned to a class yet."), findsOneWidget);
  });

  testWidgets("shows the class's agenda grid even when empty", (tester) async {
    when(() => mockClasses.fetchForTeacher('teacher-1')).thenAnswer((_) async => [_classGroup()]);

    await pumpScreen(
      tester,
      extra: [
        scheduleEntriesProvider((type: 'class', refId: 'class-1')).overrideWith((ref) async => []),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Month view'), findsOneWidget);
    expect(find.text('No events'), findsWidgets);
  });

  testWidgets("shows the class's schedule entries when present", (tester) async {
    when(() => mockClasses.fetchForTeacher('teacher-1')).thenAnswer((_) async => [_classGroup()]);
    final entries = [
      ScheduleEntry(
        id: 'entry-1',
        type: 'class',
        refId: 'class-1',
        centerId: 'center-1',
        day: 'Monday',
        startTime: '08:00',
        endTime: '09:00',
        label: 'Art',
        color: '26A69A',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        createdBy: 'teacher-1',
        updatedBy: 'teacher-1',
      ),
    ];

    await pumpScreen(
      tester,
      extra: [
        scheduleEntriesProvider((type: 'class', refId: 'class-1'))
            .overrideWith((ref) async => entries),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Mon'), findsOneWidget);
    expect(find.text('Art'), findsOneWidget);
  });
}
