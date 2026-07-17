import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_flutter/core/auth/auth_service.dart';
import 'package:test_flutter/core/models/app_user.dart';
import 'package:test_flutter/core/models/schedule.dart';
import 'package:test_flutter/core/services/schedule_service.dart';
import 'package:test_flutter/features/teacher/screens/teacher_schedule_screen.dart';

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

void main() {
  testWidgets('shows empty state when teacher has no schedule', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(_teacher())),
          scheduleProvider((type: 'teacher', refId: 'teacher-1'))
              .overrideWith((ref) async => null),
        ],
        child: const MaterialApp(home: Scaffold(body: TeacherScheduleScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No schedule set yet.'), findsOneWidget);
  });

  testWidgets('shows schedule entries when present', (tester) async {
    final schedule = Schedule(
      id: 'sched-1',
      type: 'teacher',
      refId: 'teacher-1',
      centerId: 'center-1',
      entries: const [
        ScheduleEntry(day: 'Monday', startTime: '08:00', endTime: '09:00', label: 'Art'),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      createdBy: 'director-1',
      updatedBy: 'director-1',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(_teacher())),
          scheduleProvider((type: 'teacher', refId: 'teacher-1'))
              .overrideWith((ref) async => schedule),
        ],
        child: const MaterialApp(home: Scaffold(body: TeacherScheduleScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mon'), findsOneWidget);
    expect(find.text('Art'), findsOneWidget);
  });
}
