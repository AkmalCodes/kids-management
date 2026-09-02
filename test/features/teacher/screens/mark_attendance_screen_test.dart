import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kids_management/core/auth/auth_controller.dart';
import 'package:kids_management/core/models/app_user.dart';
import 'package:kids_management/core/models/attendance.dart';
import 'package:kids_management/core/models/child.dart';
import 'package:kids_management/core/controllers/attendance_controller.dart';
import 'package:kids_management/core/controllers/child_controller.dart';
import 'package:kids_management/core/controllers/photo_capture_controller.dart';
import 'package:kids_management/features/teacher/screens/mark_attendance_screen.dart';
import 'package:kids_management/features/teacher/widgets/attendance_grid_tile.dart';
import 'package:kids_management/features/teacher/screens/child_attendance_detail_screen.dart';

class MockChildController extends Mock implements ChildController {}

class MockAttendanceController extends Mock implements AttendanceController {}

class MockPhotoCaptureController extends Mock implements PhotoCaptureController {}

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

void main() {
  setUpAll(() {
    registerFallbackValue(AttendanceStatus.present);
    registerFallbackValue(XFile(''));
  });

  late MockChildController mockChildren;
  late MockAttendanceController mockAttendance;
  late MockPhotoCaptureController mockPhotoCapture;

  setUp(() {
    mockChildren = MockChildController();
    mockAttendance = MockAttendanceController();
    mockPhotoCapture = MockPhotoCaptureController();
  });

  Future<void> pumpScreen(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => Stream.value(_teacher())),
            childControllerProvider.overrideWithValue(mockChildren),
            attendanceControllerProvider.overrideWithValue(mockAttendance),
            photoCaptureControllerProvider.overrideWithValue(mockPhotoCapture),
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

  testWidgets('a child with no record today shows the unmarked badge',
      (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1'))
        .thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('status-badge-unmarked')), findsOneWidget);
  });

  testWidgets('long-press then Mark present saves and updates the badge',
      (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1'))
        .thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => []);
    when(() => mockAttendance.markAttendance(
          childId: any(named: 'childId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          status: any(named: 'status'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
          notes: any(named: 'notes'),
        )).thenAnswer(
      (_) async => Attendance(
        id: 'att-1',
        childId: 'child-1',
        centerId: 'center-1',
        date: '2026-09-01',
        status: AttendanceStatus.present,
        notes: '',
        photoPath: null,
        belongingsPhotoPath: null,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        createdBy: 'teacher-1',
        updatedBy: 'teacher-1',
      ),
    );

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(AttendanceGridTile));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark present'));
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

    // The write's returned row is applied locally rather than re-fetched, so
    // the badge must change without fetchForDate being called again.
    expect(find.byKey(const Key('status-badge-present')), findsOneWidget);
    verify(() => mockAttendance.fetchForDate(any())).called(1);
  });

  testWidgets('tapping a tile opens the detail screen', (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1'))
        .thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(AttendanceGridTile));
    await tester.pumpAndSettle();

    expect(find.byType(ChildAttendanceDetailScreen), findsOneWidget);
  });

  testWidgets(
      'long-press then Mark absent preserves the existing notes instead of blanking them',
      (tester) async {
    final existing = Attendance(
      id: 'att-1',
      childId: 'child-1',
      centerId: 'center-1',
      date: '2026-09-01',
      status: AttendanceStatus.present,
      notes: 'Ate well today',
      photoPath: null,
      belongingsPhotoPath: null,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      createdBy: 'teacher-1',
      updatedBy: 'teacher-1',
    );
    when(() => mockChildren.fetchForTeacher('teacher-1'))
        .thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => [existing]);
    when(() => mockAttendance.markAttendance(
          childId: any(named: 'childId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          status: any(named: 'status'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
          notes: any(named: 'notes'),
        )).thenAnswer(
      (_) async => Attendance(
        id: 'att-1',
        childId: 'child-1',
        centerId: 'center-1',
        date: '2026-09-01',
        status: AttendanceStatus.absent,
        notes: 'Ate well today',
        photoPath: null,
        belongingsPhotoPath: null,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        createdBy: 'teacher-1',
        updatedBy: 'teacher-1',
      ),
    );

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(AttendanceGridTile));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark absent'));
    await tester.pumpAndSettle();

    verify(() => mockAttendance.markAttendance(
          childId: 'child-1',
          centerId: 'center-1',
          date: any(named: 'date'),
          status: AttendanceStatus.absent,
          actorUid: 'teacher-1',
          existingId: 'att-1',
          notes: 'Ate well today',
        )).called(1);
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
}
