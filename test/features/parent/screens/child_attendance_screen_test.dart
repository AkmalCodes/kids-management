import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/auth/auth_service.dart';
import 'package:test_flutter/core/models/app_user.dart';
import 'package:test_flutter/core/models/attendance.dart';
import 'package:test_flutter/core/models/child.dart';
import 'package:test_flutter/core/services/attendance_service.dart';
import 'package:test_flutter/core/services/child_service.dart';
import 'package:test_flutter/features/parent/screens/child_attendance_screen.dart';

class MockChildService extends Mock implements ChildService {}

class MockAttendanceService extends Mock implements AttendanceService {}

AppUser _parent() => AppUser(
  id: 'parent-1',
  role: 'parent',
  name: 'Parent',
  phone: '',
  centerId: 'center-1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

Child _child() => Child(
  id: 'child-1',
  name: 'Alice',
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

Attendance _record(String date, AttendanceStatus status) => Attendance(
  id: 'att-$date',
  childId: 'child-1',
  centerId: 'center-1',
  date: date,
  status: status,
  notes: '',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'teacher-1',
  updatedBy: 'teacher-1',
);

void main() {
  late MockChildService mockChildren;
  late MockAttendanceService mockAttendance;

  setUp(() {
    mockChildren = MockChildService();
    mockAttendance = MockAttendanceService();
  });

  Future<void> pumpScreen(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => Stream.value(_parent())),
            childServiceProvider.overrideWithValue(mockChildren),
            attendanceServiceProvider.overrideWithValue(mockAttendance),
          ],
          child: const MaterialApp(home: Scaffold(body: ChildAttendanceScreen())),
        ),
      );

  testWidgets('shows a message when no children are linked', (tester) async {
    when(() => mockChildren.fetchForParent('parent-1')).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('No children linked to your account yet.'), findsOneWidget);
  });

  testWidgets('shows attendance history for the linked child', (tester) async {
    when(() => mockChildren.fetchForParent('parent-1'))
        .thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForChild('child-1')).thenAnswer(
      (_) async => [_record('2026-07-17', AttendanceStatus.present)],
    );

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('2026-07-17'), findsOneWidget);
    expect(find.text('Present'), findsOneWidget);
  });
}
