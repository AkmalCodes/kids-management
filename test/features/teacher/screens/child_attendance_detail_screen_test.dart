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
import 'package:kids_management/core/controllers/photo_capture_controller.dart';
import 'package:kids_management/features/teacher/screens/child_attendance_detail_screen.dart';

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

Child _child({String allergies = ''}) => Child(
  id: 'child-1',
  name: 'Alice',
  dob: DateTime(2022, 1, 1),
  centerId: 'center-1',
  className: 'Sunflower',
  teacherId: 'teacher-1',
  allergies: allergies,
  notes: 'Naps after lunch',
  enrolledAt: DateTime(2026),
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

Attendance _saved(AttendanceStatus status) => Attendance(
  id: 'att-1',
  childId: 'child-1',
  centerId: 'center-1',
  date: '2026-09-01',
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
  setUpAll(() {
    registerFallbackValue(AttendanceStatus.present);
    registerFallbackValue(XFile(''));
  });

  late MockAttendanceController mockAttendance;
  late MockPhotoCaptureController mockPhotoCapture;

  setUp(() {
    mockAttendance = MockAttendanceController();
    mockPhotoCapture = MockPhotoCaptureController();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Child? child,
    Attendance? initial,
    ValueChanged<Attendance>? onChanged,
  }) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => Stream.value(_teacher())),
            attendanceControllerProvider.overrideWithValue(mockAttendance),
            photoCaptureControllerProvider.overrideWithValue(mockPhotoCapture),
          ],
          child: MaterialApp(
            home: ChildAttendanceDetailScreen(
              child: child ?? _child(),
              date: '2026-09-01',
              initialAttendance: initial,
              onChanged: onChanged ?? (_) {},
            ),
          ),
        ),
      );

  testWidgets('shows the allergy chip when the child has allergies',
      (tester) async {
    await pumpScreen(tester, child: _child(allergies: 'Peanuts'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('allergy-chip')), findsOneWidget);
    expect(find.textContaining('Peanuts'), findsWidgets);
  });

  testWidgets('omits the allergy chip when there are no allergies',
      (tester) async {
    await pumpScreen(tester, child: _child());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('allergy-chip')), findsNothing);
  });

  testWidgets('child details start collapsed and expand on tap', (tester) async {
    await pumpScreen(tester, child: _child());
    await tester.pumpAndSettle();

    expect(find.text('Naps after lunch'), findsNothing);

    // ListView builds rows lazily, so 'Child details' -- below the notes
    // field and Save notes button -- isn't built until scrolled into view.
    // A single drag (rather than scrollUntilVisible's incremental steps)
    // avoids a transient frame where the row briefly exists twice.
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Child details'));
    await tester.pumpAndSettle();

    expect(find.text('Naps after lunch'), findsOneWidget);
    expect(find.text('Sunflower'), findsWidgets);
  });

  testWidgets('marking present saves and reports the new record',
      (tester) async {
    Attendance? reported;
    when(() => mockAttendance.markAttendance(
          childId: any(named: 'childId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          status: any(named: 'status'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
          notes: any(named: 'notes'),
        )).thenAnswer((_) async => _saved(AttendanceStatus.present));

    await pumpScreen(tester, onChanged: (a) => reported = a);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();

    verify(() => mockAttendance.markAttendance(
          childId: 'child-1',
          centerId: 'center-1',
          date: '2026-09-01',
          status: AttendanceStatus.present,
          actorUid: 'teacher-1',
          existingId: null,
        )).called(1);
    expect(reported?.status, AttendanceStatus.present);
  });

  testWidgets('does nothing when there is no signed-in user', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(null)),
          attendanceControllerProvider.overrideWithValue(mockAttendance),
          photoCaptureControllerProvider.overrideWithValue(mockPhotoCapture),
        ],
        child: MaterialApp(
          home: ChildAttendanceDetailScreen(
            child: _child(),
            date: '2026-09-01',
            initialAttendance: null,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Present'));
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

  testWidgets('saving notes passes the typed text through', (tester) async {
    when(() => mockAttendance.markAttendance(
          childId: any(named: 'childId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          status: any(named: 'status'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
          notes: any(named: 'notes'),
        )).thenAnswer((_) async => _saved(AttendanceStatus.present));

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    // A status must exist first -- notes live on the attendance row, so
    // there is nothing to attach them to until one has been set.
    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Ate well today');
    await tester.tap(find.text('Save notes'));
    await tester.pumpAndSettle();

    verify(() => mockAttendance.markAttendance(
          childId: 'child-1',
          centerId: 'center-1',
          date: '2026-09-01',
          status: AttendanceStatus.present,
          actorUid: 'teacher-1',
          existingId: 'att-1',
          notes: 'Ate well today',
        )).called(1);
  });
}
