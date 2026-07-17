import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/models/attendance.dart';
import 'package:test_flutter/core/models/child.dart';
import 'package:test_flutter/core/services/attendance_service.dart';
import 'package:test_flutter/core/services/child_service.dart';
import 'package:test_flutter/features/director/screens/director_attendance_screen.dart';

class MockChildService extends Mock implements ChildService {}

class MockAttendanceService extends Mock implements AttendanceService {}

Child _child(String id, String name) => Child(
  id: id,
  name: name,
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

Attendance _record(String childId, AttendanceStatus status) => Attendance(
  id: 'att-$childId',
  childId: childId,
  centerId: 'center-1',
  date: '2026-07-17',
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
            childServiceProvider.overrideWithValue(mockChildren),
            attendanceServiceProvider.overrideWithValue(mockAttendance),
          ],
          child: const MaterialApp(home: Scaffold(body: DirectorAttendanceScreen())),
        ),
      );

  testWidgets('shows a message when no children are enrolled', (tester) async {
    when(() => mockChildren.fetchAll()).thenAnswer((_) async => []);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('No children enrolled yet.'), findsOneWidget);
  });

  testWidgets('shows marked and unmarked children', (tester) async {
    when(() => mockChildren.fetchAll())
        .thenAnswer((_) async => [_child('child-1', 'Alice'), _child('child-2', 'Bob')]);
    when(() => mockAttendance.fetchForDate(any()))
        .thenAnswer((_) async => [_record('child-1', AttendanceStatus.present)]);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Present'), findsOneWidget);
    expect(find.text('Not marked'), findsOneWidget);
  });
}
