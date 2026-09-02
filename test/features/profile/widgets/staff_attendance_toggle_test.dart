import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kids_management/core/auth/auth_controller.dart';
import 'package:kids_management/core/models/app_user.dart';
import 'package:kids_management/core/models/attendance.dart';
import 'package:kids_management/core/models/staff_attendance.dart';
import 'package:kids_management/core/controllers/staff_attendance_controller.dart';
import 'package:kids_management/features/profile/widgets/staff_attendance_toggle.dart';

class MockStaffAttendanceController extends Mock implements StaffAttendanceController {}

AppUser _teacher({String? centerId = 'center-1'}) => AppUser(
  id: 'teacher-1',
  role: 'teacher',
  name: 'Alice',
  phone: '',
  centerId: centerId,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

StaffAttendance _saved(AttendanceStatus status) => StaffAttendance(
  id: 'sa-1',
  staffId: 'teacher-1',
  centerId: 'center-1',
  date: '2026-09-02',
  status: status,
  notes: '',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'teacher-1',
  updatedBy: 'teacher-1',
);

void main() {
  setUpAll(() {
    registerFallbackValue(AttendanceStatus.present);
  });

  late MockStaffAttendanceController mockController;

  setUp(() {
    mockController = MockStaffAttendanceController();
  });

  Future<void> pumpToggle(WidgetTester tester, {AppUser? user}) => tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => Stream.value(user ?? _teacher())),
            staffAttendanceControllerProvider.overrideWithValue(mockController),
          ],
          child: const MaterialApp(home: Scaffold(body: StaffAttendanceToggle())),
        ),
      );

  testWidgets('shows Present and Absent choices when nothing is marked yet',
      (tester) async {
    when(() => mockController.fetchForDate(any())).thenAnswer((_) async => []);

    await pumpToggle(tester);
    await tester.pumpAndSettle();

    expect(find.text('Present'), findsOneWidget);
    expect(find.text('Absent'), findsOneWidget);
  });

  testWidgets('reflects an existing record for today', (tester) async {
    when(() => mockController.fetchForDate(any()))
        .thenAnswer((_) async => [_saved(AttendanceStatus.present)]);

    await pumpToggle(tester);
    await tester.pumpAndSettle();

    final presentChip = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('Present'), matching: find.byType(ChoiceChip)),
    );
    expect(presentChip.selected, isTrue);
  });

  testWidgets("only shows this staff member's own record, not another teacher's",
      (tester) async {
    // fetchForDate returns every staff member's row -- the widget must
    // filter to its own before deciding what is selected.
    final other = StaffAttendance(
      id: 'sa-2',
      staffId: 'someone-else',
      centerId: 'center-1',
      date: '2026-09-02',
      status: AttendanceStatus.absent,
      notes: '',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      createdBy: 'someone-else',
      updatedBy: 'someone-else',
    );
    when(() => mockController.fetchForDate(any())).thenAnswer((_) async => [other]);

    await pumpToggle(tester);
    await tester.pumpAndSettle();

    final presentChip = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('Present'), matching: find.byType(ChoiceChip)),
    );
    final absentChip = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('Absent'), matching: find.byType(ChoiceChip)),
    );
    expect(presentChip.selected, isFalse);
    expect(absentChip.selected, isFalse);
  });

  testWidgets("tapping Present calls markAttendance with the signed-in user's own id",
      (tester) async {
    when(() => mockController.fetchForDate(any())).thenAnswer((_) async => []);
    when(() => mockController.markAttendance(
          staffId: any(named: 'staffId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          status: any(named: 'status'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
          notes: any(named: 'notes'),
        )).thenAnswer((_) async => _saved(AttendanceStatus.present));

    await pumpToggle(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();

    verify(() => mockController.markAttendance(
          staffId: 'teacher-1',
          centerId: 'center-1',
          date: any(named: 'date'),
          status: AttendanceStatus.present,
          actorUid: 'teacher-1',
          existingId: null,
        )).called(1);
  });

  testWidgets('marking again updates the same row via existingId', (tester) async {
    when(() => mockController.fetchForDate(any()))
        .thenAnswer((_) async => [_saved(AttendanceStatus.present)]);
    when(() => mockController.markAttendance(
          staffId: any(named: 'staffId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          status: any(named: 'status'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
          notes: any(named: 'notes'),
        )).thenAnswer((_) async => _saved(AttendanceStatus.absent));

    await pumpToggle(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Absent'));
    await tester.pumpAndSettle();

    verify(() => mockController.markAttendance(
          staffId: 'teacher-1',
          centerId: 'center-1',
          date: any(named: 'date'),
          status: AttendanceStatus.absent,
          actorUid: 'teacher-1',
          existingId: 'sa-1',
        )).called(1);
  });

  testWidgets('shows an error message when saving fails', (tester) async {
    when(() => mockController.fetchForDate(any())).thenAnswer((_) async => []);
    when(() => mockController.markAttendance(
          staffId: any(named: 'staffId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          status: any(named: 'status'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
          notes: any(named: 'notes'),
        )).thenThrow(Exception('network down'));

    await pumpToggle(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not save attendance'), findsOneWidget);
  });

  testWidgets('renders nothing when the signed-in teacher has no center',
      (tester) async {
    // AppUser.centerId is nullable; markAttendance requires a non-null
    // center_id, so with none the control must not appear rather than crash.
    await pumpToggle(tester, user: _teacher(centerId: null));
    await tester.pumpAndSettle();

    expect(find.byType(StaffAttendanceToggle), findsOneWidget);
    expect(find.text('Present'), findsNothing);
  });
}
