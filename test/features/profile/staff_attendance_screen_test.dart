import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kawankecil/core/auth/auth_controller.dart';
import 'package:kawankecil/core/models/app_user.dart';
import 'package:kawankecil/core/models/attendance.dart';
import 'package:kawankecil/core/models/staff_attendance.dart';
import 'package:kawankecil/core/controllers/staff_attendance_controller.dart';
import 'package:kawankecil/features/profile/staff_attendance_screen.dart';

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

// A different teacher's row for the same day. fetchForDate returns every staff
// member's row, so the screen must ignore this one.
StaffAttendance _foreignRow() => StaffAttendance(
  id: 'sa-2',
  staffId: 'teacher-2',
  centerId: 'center-1',
  date: '2026-09-02',
  status: AttendanceStatus.present,
  notes: '',
  clockInAt: DateTime.utc(2026, 9, 2, 9, 0),
  clockOutAt: DateTime.utc(2026, 9, 2, 17, 0),
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
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
          at: any(named: 'at'),
          existingId: any(named: 'existingId'),
        )).thenAnswer((_) async => result);
  }

  void stubClockOut(StaffAttendance result) {
    when(() => mockController.clockOut(
          id: any(named: 'id'),
          actorUid: any(named: 'actorUid'),
          at: any(named: 'at'),
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
          at: any(named: 'at'),
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
          at: any(named: 'at'),
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

    // Capture the `at` argument: this is the recorded-timestamp contract -- the
    // value passed here is exactly what the confirm dialog showed and what the
    // controller will store, so it must be a real now()-ish DateTime, not a
    // second now() read later inside the controller.
    final captured = verify(() => mockController.clockIn(
          staffId: 'teacher-1',
          centerId: 'center-1',
          date: any(named: 'date'),
          actorUid: 'teacher-1',
          at: captureAny(named: 'at'),
          existingId: null,
        )).captured;
    expect(captured, hasLength(1));
    final at = captured.single as DateTime;
    expect(
      DateTime.now().difference(at).abs(),
      lessThan(const Duration(seconds: 2)),
      reason: 'clockIn(at:) must be the moment the teacher confirmed',
    );
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
          at: any(named: 'at'),
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

    // Capture `at` here too -- the clock-out timestamp is payroll data on the
    // same footing as clock-in.
    final captured = verify(() => mockController.clockOut(
          id: 'sa-1',
          actorUid: 'teacher-1',
          at: captureAny(named: 'at'),
        )).captured;
    expect(captured, hasLength(1));
    final at = captured.single as DateTime;
    expect(
      DateTime.now().difference(at).abs(),
      lessThan(const Duration(seconds: 2)),
      reason: 'clockOut(at:) must be the moment the teacher confirmed',
    );
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
          at: any(named: 'at'),
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
          at: any(named: 'at'),
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

  testWidgets('a failed initial load shows an error + Retry, not a bare Clock in',
      (tester) async {
    when(() => mockController.fetchForDate(any()))
        .thenThrow(Exception('network down'));

    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load today's attendance."), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    // The bug this guards: an errored load used to fall through to the data
    // branch and render exactly like "nothing recorded yet".
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('--:--'), findsNothing);
  });

  testWidgets('tapping Retry after a failed load recovers the normal state',
      (tester) async {
    var calls = 0;
    when(() => mockController.fetchForDate(any())).thenAnswer((_) async {
      calls++;
      if (calls == 1) throw Exception('network down');
      return [];
    });

    await pump(tester);
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load today's attendance."), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load today's attendance."), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Clock in'), findsOneWidget);
  });

  testWidgets("only shows this staff member's own record, not another teacher's",
      (tester) async {
    // fetchForDate returns the whole day's roster: a foreign teacher's row
    // (clocked in 09:00, out 17:00) plus this teacher's own (clocked in 06:30).
    when(() => mockController.fetchForDate(any())).thenAnswer(
      (_) async => [
        _foreignRow(),
        _row(clockInAt: DateTime.utc(2026, 9, 2, 6, 30)),
      ],
    );

    await pump(tester);
    await tester.pumpAndSettle();

    // This teacher's own clock-in time renders...
    expect(
      find.textContaining(_hhmm(DateTime.utc(2026, 9, 2, 6, 30).toLocal())),
      findsWidgets,
    );
    // ...and the foreign row's times do not leak in.
    expect(
      find.textContaining(_hhmm(DateTime.utc(2026, 9, 2, 9, 0).toLocal())),
      findsNothing,
    );
    expect(
      find.textContaining(_hhmm(DateTime.utc(2026, 9, 2, 17, 0).toLocal())),
      findsNothing,
    );
    // This teacher has clocked in but not out -> Clock out button, not a
    // locked (button-less) day as the foreign fully-clocked row would imply.
    expect(find.widgetWithText(FilledButton, 'Clock out'), findsOneWidget);
  });
}

// Local mirror of lib/shared/util/date_display.dart's hourMinute, so the test
// asserts on the same string the screen renders without importing the widget's
// own helper indirectly.
String _hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
