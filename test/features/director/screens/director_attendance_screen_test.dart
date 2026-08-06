import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/models/attendance.dart';
import 'package:test_flutter/core/models/child.dart';
import 'package:test_flutter/core/controllers/attendance_controller.dart';
import 'package:test_flutter/core/controllers/child_controller.dart';
import 'package:test_flutter/core/controllers/class_controller.dart';
import 'package:test_flutter/features/director/screens/director_attendance_screen.dart';
import 'package:test_flutter/shared/widgets/signed_photo_thumbnail.dart';

class MockChildController extends Mock implements ChildController {}

class MockAttendanceController extends Mock implements AttendanceController {}

class MockClassController extends Mock implements ClassController {}

Child _child(String id, String name) => Child(
  id: id,
  name: name,
  dob: DateTime(2022, 1, 1),
  centerId: 'center-1',
  className: '',
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
  photoPath: null,
  belongingsPhotoPath: null,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'teacher-1',
  updatedBy: 'teacher-1',
);

void main() {
  late MockChildController mockChildren;
  late MockAttendanceController mockAttendance;
  late MockClassController mockClasses;

  setUp(() {
    mockChildren = MockChildController();
    mockAttendance = MockAttendanceController();
    mockClasses = MockClassController();
    when(() => mockClasses.fetchAll()).thenAnswer((_) async => []);
  });

  Future<void> pumpScreen(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          overrides: [
            childControllerProvider.overrideWithValue(mockChildren),
            attendanceControllerProvider.overrideWithValue(mockAttendance),
            classControllerProvider.overrideWithValue(mockClasses),
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

  testWidgets('a card starts collapsed and expands to show the photos on tap',
      (tester) async {
    final record = Attendance(
      id: 'att-child-1',
      childId: 'child-1',
      centerId: 'center-1',
      date: '2026-07-17',
      status: AttendanceStatus.present,
      notes: '',
      photoPath: 'child-1/2026-07-17.jpg',
      belongingsPhotoPath: 'child-1/2026-07-17-belongings.jpg',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      createdBy: 'teacher-1',
      updatedBy: 'teacher-1',
    );
    when(() => mockChildren.fetchAll()).thenAnswer((_) async => [_child('child-1', 'Alice')]);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => [record]);
    // Never resolves -- keeps the signed-URL futures pending so CircleAvatar
    // never attempts a real network image decode (which the test env can't).
    when(() => mockAttendance.getSignedPhotoUrl(any()))
        .thenAnswer((_) => Completer<String>().future);

    await pumpScreen(tester);
    await tester.pump();

    // Collapsed: the leading avatar is the child's profile picture (absent
    // here), not the check-in photo -- so no photo thumbnails yet.
    expect(find.byType(SignedPhotoThumbnail), findsNothing);

    await tester.tap(find.text('Alice'));
    await tester.pump();

    // Expanded shows the check-in and belongings photo slots.
    expect(find.byType(SignedPhotoThumbnail), findsNWidgets(2));
    expect(find.text('Check-in photo'), findsOneWidget);
    expect(find.text('Belongings photo'), findsOneWidget);
  });
}
