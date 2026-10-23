import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kawankecil/core/auth/auth_controller.dart';
import 'package:kawankecil/core/models/app_user.dart';
import 'package:kawankecil/core/models/attendance.dart';
import 'package:kawankecil/core/models/child.dart';
import 'package:kawankecil/core/models/staff_attendance.dart';
import 'package:kawankecil/core/controllers/attendance_controller.dart';
import 'package:kawankecil/core/controllers/child_controller.dart';
import 'package:kawankecil/core/controllers/teacher_controller.dart';
import 'package:kawankecil/core/controllers/staff_attendance_controller.dart';
import 'package:kawankecil/features/teacher/screens/mark_attendance_screen.dart';
import 'package:kawankecil/features/teacher/widgets/attendance_grid_tile.dart';
import 'package:kawankecil/features/teacher/widgets/staff_grid_tile.dart';
import 'package:kawankecil/features/teacher/widgets/attendance_check_in_sheet.dart';
import 'package:kawankecil/core/controllers/photo_capture_controller.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kawankecil/features/profile/staff_attendance_screen.dart';
import 'package:kawankecil/features/profile/person_detail_screen.dart';

class MockChildController extends Mock implements ChildController {}

class MockAttendanceController extends Mock implements AttendanceController {}

class MockTeacherController extends Mock implements TeacherController {}

class MockStaffAttendanceController extends Mock implements StaffAttendanceController {}

class MockPhotoCaptureController extends Mock implements PhotoCaptureController {}

Attendance _att(String childId, AttendanceStatus status, {String id = 'att-1', String notes = '', DateTime? at}) =>
    Attendance(
      id: id,
      childId: childId,
      centerId: 'center-1',
      date: '2026-09-01',
      status: status,
      notes: notes,
      photoPath: null,
      belongingsPhotoPath: null,
      createdAt: at ?? DateTime(2026, 9, 1, 8, 5),
      updatedAt: DateTime(2026),
      createdBy: 'teacher-1',
      updatedBy: 'teacher-1',
    );

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

// A co-teacher returned by TeacherController.fetchCoTeachers -- role teacher,
// HR fields null (the projection that read omits them).
AppUser _coTeacher(String id, String name) => AppUser(
  id: id,
  role: 'teacher',
  name: name,
  phone: '',
  centerId: 'center-1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

// The signed-in teacher's own staff_attendance row for today. Mirrors the
// _row helper in staff_attendance_screen_test.dart.
StaffAttendance _staffRow({DateTime? clockInAt, DateTime? clockOutAt}) => StaffAttendance(
  id: 'sa-1',
  staffId: 'teacher-1',
  centerId: 'center-1',
  date: DateTime.now().toIso8601String().substring(0, 10),
  status: AttendanceStatus.present,
  notes: '',
  clockInAt: clockInAt,
  clockOutAt: clockOutAt,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'teacher-1',
  updatedBy: 'teacher-1',
);

void main() {
  setUpAll(() {
    registerFallbackValue(AttendanceStatus.present);
    registerFallbackValue(XFile(''));
  });

  late MockChildController mockChildren;
  late MockAttendanceController mockAttendance;
  late MockTeacherController mockTeacherCtl;
  late MockStaffAttendanceController mockStaffAtt;
  late MockPhotoCaptureController mockPhoto;

  setUp(() {
    mockChildren = MockChildController();
    mockAttendance = MockAttendanceController();
    mockTeacherCtl = MockTeacherController();
    mockStaffAtt = MockStaffAttendanceController();
    mockPhoto = MockPhotoCaptureController();
    // The camera opens when a waiting child is tapped; null = cancelled.
    when(() => mockPhoto.captureFromCamera()).thenAnswer((_) async => null);
    // Defaults so tests that only care about one grid don't have to stub the
    // other three _load() calls. `_load` awaits all of childController,
    // attendanceController, teacherController and staffAttendanceController;
    // an unstubbed one throws, the FutureBuilder never gets data, and the
    // AppLoader's indeterminate spinner makes pumpAndSettle time out. Any test
    // that needs specific data just re-stubs the relevant one.
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => []);
    when(() => mockTeacherCtl.fetchCoTeachers(any())).thenAnswer((_) async => []);
    when(() => mockStaffAtt.fetchForDate(any())).thenAnswer((_) async => []);
  });

  Future<void> pumpScreen(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => Stream.value(_teacher())),
            childControllerProvider.overrideWithValue(mockChildren),
            attendanceControllerProvider.overrideWithValue(mockAttendance),
            teacherControllerProvider.overrideWithValue(mockTeacherCtl),
            staffAttendanceControllerProvider.overrideWithValue(mockStaffAtt),
            photoCaptureControllerProvider.overrideWithValue(mockPhoto),
          ],
          child: const MaterialApp(home: Scaffold(body: MarkAttendanceScreen())),
        ),
      );

  testWidgets('shows a message when the teacher has no children assigned',
      (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1')).thenAnswer((_) async => []);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('No children assigned to you yet.'), findsOneWidget);
  });

  testWidgets('renders one grid tile per child', (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1')).thenAnswer(
      (_) async => [_child(id: 'child-1', name: 'Alice'), _child(id: 'child-2', name: 'Bob')],
    );
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.byType(AttendanceGridTile), findsNWidgets(2));
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
  });

  void stubMark(Attendance Function(Invocation) answer) {
    when(() => mockAttendance.markAttendance(
          childId: any(named: 'childId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          status: any(named: 'status'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
          notes: any(named: 'notes'),
        )).thenAnswer((inv) async => answer(inv));
  }

  testWidgets('a child with no record today is waiting: faded, "Check in", no badge',
      (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1')).thenAnswer((_) async => [_child()]);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('WAITING · 1'), findsOneWidget);
    expect(find.byKey(const Key('status-waiting')), findsOneWidget);
    expect(find.byKey(const Key('status-badge-present')), findsNothing);
  });

  testWidgets('children are grouped into waiting / here / absent with counts',
      (tester) async {
    // Tall enough that every section is built (slivers build lazily).
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    when(() => mockChildren.fetchForTeacher('teacher-1')).thenAnswer((_) async => [
          _child(id: 'c1', name: 'Alice'),
          _child(id: 'c2', name: 'Bob'),
          _child(id: 'c3', name: 'Cara'),
          _child(id: 'c4', name: 'Dan'),
        ]);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => [
          _att('c2', AttendanceStatus.present, id: 'a2'),
          _att('c3', AttendanceStatus.late, id: 'a3'),
          _att('c4', AttendanceStatus.excused, id: 'a4'),
        ]);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('WAITING · 1'), findsOneWidget);
    expect(find.text('HERE · 2'), findsOneWidget); // present + late
    expect(find.text('ABSENT · 1'), findsOneWidget); // excused counts as away
    expect(find.descendant(of: find.byKey(const Key('count-here')), matching: find.text('2')),
        findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('count-waiting')), matching: find.text('1')),
        findsOneWidget);
    // Arrival time under a child who's here (local 08:05).
    expect(find.text('08:05'), findsNWidgets(2));
  });

  testWidgets('tapping a waiting child opens the camera, then the check-in sheet',
      (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1')).thenAnswer((_) async => [_child()]);

    await pumpScreen(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AttendanceGridTile));
    await tester.pumpAndSettle();

    verify(() => mockPhoto.captureFromCamera()).called(1);
    expect(find.byType(AttendanceCheckInSheet), findsOneWidget);
    expect(find.text('Check in Alice'), findsOneWidget);
  });

  testWidgets('checking in from the sheet saves and moves the child to HERE, no re-fetch',
      (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1')).thenAnswer((_) async => [_child()]);
    stubMark((_) => _att('child-1', AttendanceStatus.present));

    await pumpScreen(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AttendanceGridTile));
    await tester.pumpAndSettle();
    // The sheet scrolls; bring its button into the (small) test window.
    await tester.ensureVisible(find.text('Check in Alice'));
    await tester.tap(find.text('Check in Alice'));
    await tester.pumpAndSettle();

    verify(() => mockAttendance.markAttendance(
          childId: 'child-1',
          centerId: 'center-1',
          date: any(named: 'date'),
          status: AttendanceStatus.present,
          actorUid: 'teacher-1',
          existingId: null,
          notes: '',
        )).called(1);
    expect(find.byType(AttendanceCheckInSheet), findsNothing);
    expect(find.text('HERE · 1'), findsOneWidget);
    expect(find.byKey(const Key('status-badge-present')), findsOneWidget);
    verify(() => mockAttendance.fetchForDate(any())).called(1);
  });

  testWidgets('tapping a child who is already here opens the sheet pre-filled, no camera',
      (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1')).thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForDate(any()))
        .thenAnswer((_) async => [_att('child-1', AttendanceStatus.present, notes: 'Ate well')]);

    await pumpScreen(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AttendanceGridTile));
    await tester.pumpAndSettle();

    verifyNever(() => mockPhoto.captureFromCamera());
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Ate well'), findsOneWidget); // note shown, editable
  });

  testWidgets('"Mark the rest" asks, then marks every waiting child absent', (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1')).thenAnswer((_) async => [
          _child(id: 'c1', name: 'Alice'),
          _child(id: 'c2', name: 'Bob'),
        ]);
    stubMark((inv) => _att(inv.namedArguments[#childId] as String, AttendanceStatus.absent,
        id: 'a-${inv.namedArguments[#childId]}'));

    await pumpScreen(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark the rest…'));
    await tester.pumpAndSettle();
    expect(find.text('Mark 2 absent?'), findsOneWidget);

    await tester.tap(find.text('Mark absent'));
    await tester.pumpAndSettle();

    for (final id in ['c1', 'c2']) {
      verify(() => mockAttendance.markAttendance(
            childId: id,
            centerId: 'center-1',
            date: any(named: 'date'),
            status: AttendanceStatus.absent,
            actorUid: 'teacher-1',
            existingId: any(named: 'existingId'),
            notes: any(named: 'notes'),
          )).called(1);
    }
    expect(find.text('ABSENT · 2'), findsOneWidget);
    expect(find.text('Mark the rest…'), findsNothing); // nobody waiting now
  });

  testWidgets('cancelling "Mark the rest" writes nothing', (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1')).thenAnswer((_) async => [_child()]);

    await pumpScreen(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark the rest…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => mockAttendance.markAttendance(
          childId: any(named: 'childId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          status: any(named: 'status'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
          notes: any(named: 'notes'),
        ));
  });

  testWidgets('typing in the search bar narrows the grid to matching children',
      (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1')).thenAnswer(
      (_) async => [_child(id: 'child-1', name: 'Alice'), _child(id: 'child-2', name: 'Bob')],
    );
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.byType(AttendanceGridTile), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Ali');
    await tester.pumpAndSettle();

    expect(find.byType(AttendanceGridTile), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsNothing);
  });

  testWidgets('shows the teachers row and the class name as the title', (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1')).thenAnswer((_) async => [
          Child(
            id: 'child-1',
            name: 'Alice',
            dob: DateTime(2022, 1, 1),
            centerId: 'center-1',
            className: 'Bunga',
            teacherId: 'teacher-1',
            allergies: '',
            notes: '',
            enrolledAt: DateTime(2026),
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            createdBy: 'director-1',
            updatedBy: 'director-1',
          ),
        ]);
    await pumpScreen(tester);
    await tester.pumpAndSettle();
    expect(find.text('TEACHERS'), findsOneWidget);
    expect(find.text('Bunga'), findsOneWidget);
  });

  testWidgets('fits a 360px-wide phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    when(() => mockChildren.fetchForTeacher('teacher-1')).thenAnswer((_) async => [
          for (var i = 0; i < 6; i++) _child(id: 'c$i', name: 'Child with a long name $i'),
        ]);
    await pumpScreen(tester);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets("the signed-in teacher's own tile is first and shows the clock badge",
      (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1')).thenAnswer((_) async => []);
    when(() => mockStaffAtt.fetchForDate(any())).thenAnswer(
      (_) async => [_staffRow(clockInAt: DateTime.utc(2026, 9, 7, 6, 30))],
    );
    await pumpScreen(tester);
    await tester.pumpAndSettle();
    // one StaffGridTile (self), badge = working (clocked in, not out)
    expect(find.byType(StaffGridTile), findsOneWidget);
    expect(find.byIcon(Icons.access_time_filled), findsOneWidget);
  });

  testWidgets('a co-teacher renders with no badge', (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1')).thenAnswer((_) async => []);
    when(() => mockTeacherCtl.fetchCoTeachers('teacher-1')).thenAnswer(
      (_) async => [_coTeacher('t-2', 'Ben Ng')],
    );
    await pumpScreen(tester);
    await tester.pumpAndSettle();
    expect(find.byType(StaffGridTile), findsNWidgets(2)); // self + co-teacher
    // self is notClockedIn (no row) -> Icons.schedule once; co-teacher -> none
    expect(find.byIcon(Icons.schedule), findsOneWidget);
  });

  testWidgets('tapping the own tile opens the clock-in/out screen', (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1')).thenAnswer((_) async => []);
    await pumpScreen(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(StaffGridTile).first);
    await tester.pumpAndSettle();
    expect(find.byType(StaffAttendanceScreen), findsOneWidget);
  });

  testWidgets('tapping a co-teacher tile opens their read-only profile', (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1')).thenAnswer((_) async => []);
    when(() => mockTeacherCtl.fetchCoTeachers('teacher-1')).thenAnswer(
      (_) async => [_coTeacher('t-2', 'Ben Ng')],
    );
    await pumpScreen(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(StaffGridTile).last);
    await tester.pumpAndSettle();
    expect(find.byType(PersonDetailScreen), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    // A co-teacher has no email/phone/HR fields in fetchCoTeachers' projection,
    // and readOnly mode must drop those rows rather than show "Not provided".
    expect(find.text('Not provided'), findsNothing);
  });

  testWidgets('pulling down refetches the roster (page is kept alive between tabs)',
      (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1')).thenAnswer((_) async => []);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();
    await tester.fling(
        find.text('No children assigned to you yet.'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    verify(() => mockChildren.fetchForTeacher('teacher-1')).called(2);
  });
}
