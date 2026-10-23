import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kawankecil/core/auth/auth_controller.dart';
import 'package:kawankecil/core/models/app_user.dart';
import 'package:kawankecil/core/models/attendance.dart';
import 'package:kawankecil/core/models/child.dart';
import 'package:kawankecil/core/controllers/attendance_controller.dart';
import 'package:kawankecil/core/controllers/child_controller.dart';
import 'package:kawankecil/features/parent/screens/attendance_detail_screen.dart';
import 'package:kawankecil/features/parent/screens/child_attendance_screen.dart';

class MockChildController extends Mock implements ChildController {}

class MockAttendanceController extends Mock implements AttendanceController {}

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

Child _child({String id = 'child-1', String name = 'Alice'}) => Child(
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

Attendance _record(String date, AttendanceStatus status,
        {String notes = '', String? photoPath, String childId = 'child-1'}) =>
    Attendance(
  id: 'att-$childId-$date',
  childId: childId,
  centerId: 'center-1',
  date: date,
  status: status,
  notes: notes,
  photoPath: photoPath,
  belongingsPhotoPath: null,
  createdAt: DateTime(2026, 10, 23, 7, 52),
  updatedAt: DateTime(2026),
  createdBy: 'teacher-1',
  updatedBy: 'teacher-1',
);

void main() {
  late MockChildController mockChildren;
  late MockAttendanceController mockAttendance;

  setUp(() {
    mockChildren = MockChildController();
    mockAttendance = MockAttendanceController();
    when(() => mockAttendance.getSignedPhotoUrl(any())).thenAnswer((_) => Completer<String>().future);
  });

  Future<void> pumpScreen(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => Stream.value(_parent())),
            childControllerProvider.overrideWithValue(mockChildren),
            attendanceControllerProvider.overrideWithValue(mockAttendance),
          ],
          child: MaterialApp(home: Scaffold(body: ChildAttendanceScreen(today: DateTime(2026, 10, 23)))),
        ),
      );

  testWidgets('shows a message when no children are linked', (tester) async {
    when(() => mockChildren.fetchForParent('parent-1')).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('No children linked to your account yet.'), findsOneWidget);
  });

  testWidgets('today card: checked in, with time, photo and the teacher\'s note', (tester) async {
    when(() => mockChildren.fetchForParent('parent-1')).thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForChild('child-1')).thenAnswer((_) async => [
          _record('2026-10-23', AttendanceStatus.present, notes: 'Happy today', photoPath: 'p.jpg'),
        ]);
    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Alice is at school'), findsOneWidget);
    expect(find.text('Present · checked in 07:52'), findsOneWidget);
    expect(find.text('Note from teacher: Happy today'), findsOneWidget);
    verify(() => mockAttendance.getSignedPhotoUrl('p.jpg')).called(greaterThan(0));
  });

  testWidgets('today card: not checked in yet', (tester) async {
    when(() => mockChildren.fetchForParent('parent-1')).thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForChild('child-1')).thenAnswer((_) async => []);
    await pumpScreen(tester);
    await tester.pumpAndSettle();
    expect(find.text('Not checked in yet'), findsOneWidget);
    expect(find.text('No earlier days yet.'), findsOneWidget);
  });

  testWidgets('today card: absent today', (tester) async {
    when(() => mockChildren.fetchForParent('parent-1')).thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForChild('child-1'))
        .thenAnswer((_) async => [_record('2026-10-23', AttendanceStatus.absent, notes: 'Fever')]);
    await pumpScreen(tester);
    await tester.pumpAndSettle();
    expect(find.text('Alice is absent today'), findsOneWidget);
    expect(find.text('Fever'), findsOneWidget);
  });

  testWidgets('this week shows a badge for each marked day', (tester) async {
    when(() => mockChildren.fetchForParent('parent-1')).thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForChild('child-1')).thenAnswer((_) async => [
          _record('2026-10-23', AttendanceStatus.present),
          _record('2026-10-20', AttendanceStatus.absent),
          _record('2026-10-19', AttendanceStatus.present),
        ]);
    await pumpScreen(tester);
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('week-1')), matching: find.byKey(const Key('status-badge-present'))),
        findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('week-2')), matching: find.byKey(const Key('status-badge-absent'))),
        findsOneWidget);
    // Wednesday has no record: no badge.
    expect(find.descendant(of: find.byKey(const Key('week-3')), matching: find.byType(Icon)), findsNothing);
  });

  testWidgets('earlier days list newest first and open the day', (tester) async {
    when(() => mockChildren.fetchForParent('parent-1')).thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForChild('child-1')).thenAnswer((_) async => [
          _record('2026-10-22', AttendanceStatus.present, notes: 'Painted a rainbow'),
          _record('2026-10-21', AttendanceStatus.absent),
        ]);
    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Thursday, 22 Oct'), findsOneWidget);
    expect(find.text('07:52 · Present'), findsOneWidget);
    expect(find.text('Wednesday, 21 Oct'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Thursday, 22 Oct')).dy,
      lessThan(tester.getTopLeft(find.text('Wednesday, 21 Oct')).dy),
    );

    await tester.tap(find.text('Thursday, 22 Oct'));
    await tester.pumpAndSettle();
    expect(find.byType(AttendanceDetailScreen), findsOneWidget);
    expect(find.text('Painted a rainbow'), findsOneWidget);
    expect(find.text('CHECK-IN PHOTO'), findsOneWidget);
  });

  testWidgets('with two children, chips switch between them', (tester) async {
    when(() => mockChildren.fetchForParent('parent-1'))
        .thenAnswer((_) async => [_child(), _child(id: 'child-2', name: 'Adam')]);
    when(() => mockAttendance.fetchForChild('child-1'))
        .thenAnswer((_) async => [_record('2026-10-23', AttendanceStatus.present)]);
    when(() => mockAttendance.fetchForChild('child-2')).thenAnswer((_) async => []);
    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Alice is at school'), findsOneWidget);
    await tester.tap(find.text('Adam'));
    await tester.pumpAndSettle();
    expect(find.text('Not checked in yet'), findsOneWidget);
    expect(find.text('Alice is at school'), findsNothing);
  });

  testWidgets('fits a 360px-wide phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    when(() => mockChildren.fetchForParent('parent-1'))
        .thenAnswer((_) async => [_child(name: 'Alexandra Wong Mei Ling'), _child(id: 'c2', name: 'Muhammad Adam')]);
    when(() => mockAttendance.fetchForChild(any())).thenAnswer((_) async => [
          _record('2026-10-23', AttendanceStatus.late, notes: 'A long note from the teacher about the day'),
          _record('2026-10-22', AttendanceStatus.excused),
        ]);
    await pumpScreen(tester);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
