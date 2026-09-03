import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kids_management/core/auth/auth_controller.dart';
import 'package:kids_management/core/models/app_user.dart';
import 'package:kids_management/core/models/attendance.dart';
import 'package:kids_management/core/models/staff_attendance.dart';
import 'package:kids_management/core/controllers/staff_attendance_controller.dart';
import 'package:kids_management/features/profile/staff_attendance_screen.dart';

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

StaffAttendance _row({DateTime? clockInAt, DateTime? clockOutAt}) => StaffAttendance(
  id: 'sa-1',
  staffId: 'teacher-1',
  centerId: 'center-1',
  date: '2026-09-02',
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
  late MockStaffAttendanceController mockController;

  setUp(() {
    mockController = MockStaffAttendanceController();
  });

  Future<void> pump(WidgetTester tester, {AppUser? user}) => tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => Stream.value(user ?? _teacher())),
            staffAttendanceControllerProvider.overrideWithValue(mockController),
          ],
          child: const MaterialApp(home: StaffAttendanceScreen()),
        ),
      );

  void stubClockIn(StaffAttendance result) {
    when(() => mockController.clockIn(
          staffId: any(named: 'staffId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
        )).thenAnswer((_) async => result);
  }

  void stubClockOut(StaffAttendance result) {
    when(() => mockController.clockOut(
          id: any(named: 'id'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => result);
  }

  testWidgets('shows a Clock in button when nothing is recorded for today',
      (tester) async {
    when(() => mockController.fetchForDate(any())).thenAnswer((_) async => []);

    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Clock in'), findsOneWidget);
    expect(find.text('Clock out'), findsNothing);
  });

  testWidgets('tapping Clock in opens a confirm dialog and does not write yet',
      (tester) async {
    when(() => mockController.fetchForDate(any())).thenAnswer((_) async => []);

    await pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Clock in'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('Confirm clock-in at'), findsOneWidget);
    verifyNever(() => mockController.clockIn(
          staffId: any(named: 'staffId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
        ));
  });

  testWidgets('cancelling the confirm dialog writes nothing', (tester) async {
    when(() => mockController.fetchForDate(any())).thenAnswer((_) async => []);

    await pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Clock in'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => mockController.clockIn(
          staffId: any(named: 'staffId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
        ));
  });

  testWidgets('confirming Clock in calls clockIn with the signed-in id, today, no existingId',
      (tester) async {
    when(() => mockController.fetchForDate(any())).thenAnswer((_) async => []);
    stubClockIn(_row(clockInAt: DateTime.utc(2026, 9, 2, 6, 30)));

    await pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Clock in'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    verify(() => mockController.clockIn(
          staffId: 'teacher-1',
          centerId: 'center-1',
          date: any(named: 'date'),
          actorUid: 'teacher-1',
          existingId: null,
        )).called(1);
  });

  testWidgets('confirming Clock in passes existingId when a row already exists',
      (tester) async {
    // A director pre-created today's row (status absent, no clock times).
    when(() => mockController.fetchForDate(any()))
        .thenAnswer((_) async => [_row()]);
    stubClockIn(_row(clockInAt: DateTime.utc(2026, 9, 2, 6, 30)));

    await pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Clock in'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    verify(() => mockController.clockIn(
          staffId: 'teacher-1',
          centerId: 'center-1',
          date: any(named: 'date'),
          actorUid: 'teacher-1',
          existingId: 'sa-1',
        )).called(1);
  });

  testWidgets('after clocking in, shows the recorded time and a Clock out button',
      (tester) async {
    when(() => mockController.fetchForDate(any())).thenAnswer(
      (_) async => [_row(clockInAt: DateTime.utc(2026, 9, 2, 6, 30))],
    );

    await pump(tester);
    await tester.pumpAndSettle();

    final localHhmm = _hhmm(DateTime.utc(2026, 9, 2, 6, 30).toLocal());
    expect(find.textContaining(localHhmm), findsWidgets);
    expect(find.widgetWithText(FilledButton, 'Clock out'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Clock in'), findsNothing);
  });

  testWidgets('confirming Clock out calls clockOut with the existing row id',
      (tester) async {
    when(() => mockController.fetchForDate(any())).thenAnswer(
      (_) async => [_row(clockInAt: DateTime.utc(2026, 9, 2, 6, 30))],
    );
    stubClockOut(_row(
      clockInAt: DateTime.utc(2026, 9, 2, 6, 30),
      clockOutAt: DateTime.utc(2026, 9, 2, 15, 0),
    ));

    await pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Clock out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    verify(() => mockController.clockOut(id: 'sa-1', actorUid: 'teacher-1')).called(1);
  });

  testWidgets('once both times are set, no buttons remain and both render as text',
      (tester) async {
    when(() => mockController.fetchForDate(any())).thenAnswer(
      (_) async => [
        _row(
          clockInAt: DateTime.utc(2026, 9, 2, 6, 30),
          clockOutAt: DateTime.utc(2026, 9, 2, 15, 0),
        ),
      ],
    );

    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.byType(FilledButton), findsNothing);
    expect(find.textContaining(_hhmm(DateTime.utc(2026, 9, 2, 6, 30).toLocal())), findsWidgets);
    expect(find.textContaining(_hhmm(DateTime.utc(2026, 9, 2, 15, 0).toLocal())), findsWidgets);
  });

  testWidgets('an error from clockIn surfaces a message', (tester) async {
    when(() => mockController.fetchForDate(any())).thenAnswer((_) async => []);
    when(() => mockController.clockIn(
          staffId: any(named: 'staffId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
        )).thenThrow(Exception('network down'));

    await pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Clock in'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not clock in'), findsOneWidget);
  });

  testWidgets('an error from clockOut surfaces a message', (tester) async {
    when(() => mockController.fetchForDate(any())).thenAnswer(
      (_) async => [_row(clockInAt: DateTime.utc(2026, 9, 2, 6, 30))],
    );
    when(() => mockController.clockOut(
          id: any(named: 'id'),
          actorUid: any(named: 'actorUid'),
        )).thenThrow(Exception('network down'));

    await pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Clock out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not clock out'), findsOneWidget);
  });

  testWidgets('shows nothing to clock when the teacher has no center', (tester) async {
    await pump(tester, user: _teacher(centerId: null));
    await tester.pumpAndSettle();

    expect(find.byType(FilledButton), findsNothing);
  });
}

// Local mirror of lib/shared/util/date_display.dart's hourMinute, so the test
// asserts on the same string the screen renders without importing the widget's
// own helper indirectly.
String _hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
