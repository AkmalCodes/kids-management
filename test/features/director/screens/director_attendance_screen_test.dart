import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kawankecil/core/auth/auth_controller.dart';
import 'package:kawankecil/core/models/app_user.dart';
import 'package:kawankecil/core/models/attendance.dart';
import 'package:kawankecil/core/models/child.dart';
import 'package:kawankecil/core/models/class_group.dart';
import 'package:kawankecil/core/models/staff_attendance.dart';
import 'package:kawankecil/core/controllers/attendance_controller.dart';
import 'package:kawankecil/core/controllers/child_controller.dart';
import 'package:kawankecil/core/controllers/class_controller.dart';
import 'package:kawankecil/core/controllers/staff_attendance_controller.dart';
import 'package:kawankecil/core/controllers/teacher_controller.dart';
import 'package:kawankecil/features/director/screens/director_attendance_screen.dart';
import 'package:kawankecil/features/director/widgets/staff_attendance_fix_sheet.dart';

class MockChildController extends Mock implements ChildController {}

class MockAttendanceController extends Mock implements AttendanceController {}

class MockClassController extends Mock implements ClassController {}

class MockTeacherController extends Mock implements TeacherController {}

class MockStaffAttendanceController extends Mock implements StaffAttendanceController {}

AppUser _user(String id, String name, {String role = 'teacher'}) => AppUser(
      id: id,
      role: role,
      name: name,
      phone: '',
      centerId: 'center-1',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      createdBy: 'director-1',
      updatedBy: 'director-1',
    );

Child _child(String id, String name, {String? classId}) => Child(
      id: id,
      name: name,
      dob: DateTime(2022, 1, 1),
      centerId: 'center-1',
      className: '',
      classId: classId,
      teacherId: 'teacher-1',
      allergies: '',
      notes: '',
      enrolledAt: DateTime(2026),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      createdBy: 'director-1',
      updatedBy: 'director-1',
    );

ClassGroup _class(String id, String name) => ClassGroup.fromJson({
      'id': id,
      'center_id': 'center-1',
      'name': name,
      'teacher_uids': <String>[],
      'created_at': DateTime(2026).toIso8601String(),
      'updated_at': DateTime(2026).toIso8601String(),
    });

Attendance _record(String childId, AttendanceStatus status, {String notes = ''}) => Attendance(
      id: 'att-$childId',
      childId: childId,
      centerId: 'center-1',
      date: '2026-07-17',
      status: status,
      notes: notes,
      photoPath: null,
      belongingsPhotoPath: null,
      createdAt: DateTime(2026, 7, 17, 7, 52),
      updatedAt: DateTime(2026),
      createdBy: 'teacher-1',
      updatedBy: 'teacher-1',
    );

StaffAttendance _staff(String staffId, {DateTime? inAt, DateTime? outAt, AttendanceStatus status = AttendanceStatus.present}) =>
    StaffAttendance(
      id: 'sa-$staffId',
      staffId: staffId,
      centerId: 'center-1',
      date: '2026-07-17',
      status: status,
      notes: '',
      clockInAt: inAt,
      clockOutAt: outAt,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      createdBy: staffId,
      updatedBy: staffId,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(AttendanceStatus.present);
    registerFallbackValue(DateTime(2026));
  });

  late MockChildController mockChildren;
  late MockAttendanceController mockAttendance;
  late MockClassController mockClasses;
  late MockTeacherController mockTeachers;
  late MockStaffAttendanceController mockStaff;

  setUp(() {
    mockChildren = MockChildController();
    mockAttendance = MockAttendanceController();
    mockClasses = MockClassController();
    mockTeachers = MockTeacherController();
    mockStaff = MockStaffAttendanceController();
    when(() => mockClasses.fetchAll()).thenAnswer((_) async => []);
    when(() => mockChildren.fetchAll()).thenAnswer((_) async => []);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => []);
    when(() => mockTeachers.fetchAll()).thenAnswer((_) async => []);
    when(() => mockStaff.fetchForDate(any())).thenAnswer((_) async => []);
    // Saved photos load via signed URLs; never resolve here (no network).
    when(() => mockAttendance.getSignedPhotoUrl(any())).thenAnswer((_) => Completer<String>().future);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(_user('director-1', 'Director', role: 'director'))),
          childControllerProvider.overrideWithValue(mockChildren),
          attendanceControllerProvider.overrideWithValue(mockAttendance),
          classControllerProvider.overrideWithValue(mockClasses),
          teacherControllerProvider.overrideWithValue(mockTeachers),
          staffAttendanceControllerProvider.overrideWithValue(mockStaff),
        ],
        child: const MaterialApp(home: Scaffold(body: DirectorAttendanceScreen())),
      ),
    );
    await tester.pumpAndSettle();
  }

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('shows a message when no children are enrolled', (tester) async {
    await pumpScreen(tester);
    expect(find.text('No children enrolled yet.'), findsOneWidget);
  });

  testWidgets('children are grouped by class with "x OF y HERE" and counts', (tester) async {
    tall(tester);
    when(() => mockClasses.fetchAll()).thenAnswer((_) async => [_class('k1', 'Bunga'), _class('k2', 'Melati')]);
    when(() => mockChildren.fetchAll()).thenAnswer((_) async => [
          _child('c1', 'Alice', classId: 'k1'),
          _child('c2', 'Bob', classId: 'k1'),
          _child('c3', 'Cara', classId: 'k2'),
          _child('c4', 'Dan'),
        ]);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => [
          _record('c1', AttendanceStatus.present),
          _record('c3', AttendanceStatus.absent),
        ]);

    await pumpScreen(tester);

    expect(find.text('BUNGA · 1 OF 2 HERE'), findsOneWidget);
    expect(find.text('MELATI · 0 OF 1 HERE'), findsOneWidget);
    expect(find.text('NO CLASS · 0 OF 1 HERE'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('count-here')), matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('count-waiting')), matching: find.text('2')), findsOneWidget);
    // Read-only: waiting children say "Not in yet", never "Check in".
    expect(find.text('Not in yet'), findsNWidgets(2));
    expect(find.text('Check in'), findsNothing);
  });

  testWidgets('a class chip narrows to that class', (tester) async {
    tall(tester);
    when(() => mockClasses.fetchAll()).thenAnswer((_) async => [_class('k1', 'Bunga'), _class('k2', 'Melati')]);
    when(() => mockChildren.fetchAll()).thenAnswer((_) async => [
          _child('c1', 'Alice', classId: 'k1'),
          _child('c3', 'Cara', classId: 'k2'),
        ]);
    await pumpScreen(tester);

    await tester.tap(find.text('Melati'));
    await tester.pumpAndSettle();
    expect(find.textContaining('BUNGA'), findsNothing);
    expect(find.text('MELATI · 0 OF 1 HERE'), findsOneWidget);
  });

  testWidgets("tapping a child opens their day, read-only", (tester) async {
    tall(tester);
    when(() => mockChildren.fetchAll()).thenAnswer((_) async => [_child('c1', 'Alice'), _child('c2', 'Bob')]);
    when(() => mockAttendance.fetchForDate(any()))
        .thenAnswer((_) async => [_record('c1', AttendanceStatus.present, notes: 'Slight cough')]);
    await pumpScreen(tester);

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(find.text('CHECK-IN PHOTO'), findsOneWidget);
    expect(find.text('Slight cough'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();
    expect(find.text('Not checked in yet.'), findsOneWidget);
  });

  testWidgets('a banner names a teacher who has not clocked in and opens Teachers', (tester) async {
    when(() => mockChildren.fetchAll()).thenAnswer((_) async => [_child('c1', 'Alice')]);
    when(() => mockTeachers.fetchAll()).thenAnswer((_) async => [_user('t1', 'Aina'), _user('t2', 'Priya')]);
    when(() => mockStaff.fetchForDate(any()))
        .thenAnswer((_) async => [_staff('t1', inAt: DateTime(2026, 7, 17, 7, 30))]);
    await pumpScreen(tester);

    expect(find.text("Priya hasn't clocked in"), findsOneWidget);
    await tester.tap(find.byKey(const Key('missing-teachers')));
    await tester.pumpAndSettle();
    expect(find.text('TEACHERS · 1 OF 2 CLOCKED IN'), findsOneWidget);
    expect(find.text('In 07:30 · Out —'), findsOneWidget);
    expect(find.text('Working'), findsOneWidget);
    expect(find.text('Not clocked in'), findsOneWidget);
  });

  testWidgets('an absent teacher is accounted for: no banner', (tester) async {
    when(() => mockChildren.fetchAll()).thenAnswer((_) async => [_child('c1', 'Alice')]);
    when(() => mockTeachers.fetchAll()).thenAnswer((_) async => [_user('t2', 'Priya')]);
    when(() => mockStaff.fetchForDate(any()))
        .thenAnswer((_) async => [_staff('t2', status: AttendanceStatus.absent)]);
    await pumpScreen(tester);
    expect(find.byKey(const Key('missing-teachers')), findsNothing);
  });

  group('teacher fix sheet', () {
    Future<void> openPriya(WidgetTester tester, {StaffAttendance? row}) async {
      when(() => mockTeachers.fetchAll()).thenAnswer((_) async => [_user('t2', 'Priya')]);
      when(() => mockStaff.fetchForDate(any())).thenAnswer((_) async => [?row]);
      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('view-teachers')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('teacher-row-t2')));
      await tester.pumpAndSettle();
      expect(find.byType(StaffAttendanceFixSheet), findsOneWidget);
    }

    testWidgets('Save status marks the teacher, in the director\'s centre', (tester) async {
      when(() => mockStaff.markAttendance(
            staffId: any(named: 'staffId'),
            centerId: any(named: 'centerId'),
            date: any(named: 'date'),
            status: any(named: 'status'),
            actorUid: any(named: 'actorUid'),
            existingId: any(named: 'existingId'),
            notes: any(named: 'notes'),
          )).thenAnswer((_) async => _staff('t2', status: AttendanceStatus.absent));

      await openPriya(tester);
      await tester.tap(find.byKey(const Key('status-absent')));
      await tester.enterText(find.byKey(const Key('staff-note')), 'MC');
      await tester.ensureVisible(find.text('Save status'));
      await tester.tap(find.text('Save status'));
      await tester.pumpAndSettle();

      verify(() => mockStaff.markAttendance(
            staffId: 't2',
            centerId: 'center-1',
            date: any(named: 'date'),
            status: AttendanceStatus.absent,
            actorUid: 'director-1',
            existingId: null,
            notes: 'MC',
          )).called(1);
    });

    testWidgets('a missing clock-in can be recorded at a picked time, after a confirm', (tester) async {
      when(() => mockStaff.clockIn(
            staffId: any(named: 'staffId'),
            centerId: any(named: 'centerId'),
            date: any(named: 'date'),
            actorUid: any(named: 'actorUid'),
            at: any(named: 'at'),
            existingId: any(named: 'existingId'),
          )).thenAnswer((_) async => _staff('t2', inAt: DateTime(2026, 7, 17, 8, 0)));

      await openPriya(tester);
      expect(find.byKey(const Key('record-clock-out')), findsNothing); // needs a clock-in first
      await tester.tap(find.byKey(const Key('record-clock-in')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK')); // time picker, default 08:00
      await tester.pumpAndSettle();
      expect(find.text('Record clock-in at 08:00?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Record'));
      await tester.pumpAndSettle();

      final captured = verify(() => mockStaff.clockIn(
            staffId: 't2',
            centerId: 'center-1',
            date: any(named: 'date'),
            actorUid: 'director-1',
            at: captureAny(named: 'at'),
            existingId: null,
          )).captured;
      final at = captured.single as DateTime;
      expect((at.hour, at.minute), (8, 0));
      // Now recorded: locked, and the clock-out can be recorded.
      expect(find.byKey(const Key('record-clock-in')), findsNothing);
      expect(find.byKey(const Key('record-clock-out')), findsOneWidget);
    });

    testWidgets('recorded times are locked: no way to change them', (tester) async {
      await openPriya(tester,
          row: _staff('t2', inAt: DateTime(2026, 7, 17, 7, 30), outAt: DateTime(2026, 7, 17, 16, 0)));
      expect(find.byKey(const Key('record-clock-in')), findsNothing);
      expect(find.byKey(const Key('record-clock-out')), findsNothing);
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(2));
    });
  });

  testWidgets('pulling down refetches (page is kept alive between tabs)', (tester) async {
    when(() => mockChildren.fetchAll()).thenAnswer((_) async => [_child('c1', 'Alice')]);
    await pumpScreen(tester);
    await tester.fling(find.text('Attendance'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    verify(() => mockChildren.fetchAll()).called(2);
  });

  testWidgets('fits a 360px-wide phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    when(() => mockClasses.fetchAll()).thenAnswer((_) async => [_class('k1', 'A very long class name')]);
    when(() => mockChildren.fetchAll()).thenAnswer((_) async => [
          for (var i = 0; i < 7; i++) _child('c$i', 'Child with a long name $i', classId: 'k1'),
        ]);
    when(() => mockTeachers.fetchAll()).thenAnswer((_) async => [_user('t2', 'A teacher with a very long name')]);
    await pumpScreen(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('view-teachers')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
