import 'dart:async';
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
import 'package:kids_management/shared/widgets/signed_photo_thumbnail.dart';

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

Attendance _withPhotos({
  String? photoPath,
  String? belongingsPhotoPath,
  AttendanceStatus status = AttendanceStatus.present,
}) => Attendance(
  id: 'att-1',
  childId: 'child-1',
  centerId: 'center-1',
  date: '2026-09-01',
  status: status,
  notes: '',
  photoPath: photoPath,
  belongingsPhotoPath: belongingsPhotoPath,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'teacher-1',
  updatedBy: 'teacher-1',
);

// Reaches the InkWell inside a photo slot so a test can assert whether the
// slot is tappable. A disabled slot passes a null onTap rather than swapping
// the widget out, so inspecting the callback is the only way to tell.
InkWell _inkWellIn(WidgetTester tester, Key slotKey) => tester.widget<InkWell>(
      find.descendant(of: find.byKey(slotKey), matching: find.byType(InkWell)),
    );

// Tapping the slot's Key hits the whole Column -- label included -- whose
// centre can miss the tappable area. Target the InkWell itself.
Finder _slotTapTarget(Key slotKey) =>
    find.descendant(of: find.byKey(slotKey), matching: find.byType(InkWell));

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

  // --- photo handling ------------------------------------------------------
  // Ported from mark_attendance_screen_test.dart when the expand-in-place card
  // was replaced by this screen. The photo flows moved here but their tests
  // were dropped in the move, leaving the app's only photo-editing surface
  // uncovered.

  testWidgets('photo slots are disabled until a status has been set for the day',
      (tester) async {
    // A photo attaches to an attendance row, so with no row there is nothing
    // to attach it to.
    await pumpScreen(tester, initial: null);
    await tester.pumpAndSettle();

    expect(_inkWellIn(tester, const Key('checkin-photo')).onTap, isNull);
    expect(_inkWellIn(tester, const Key('belongings-photo')).onTap, isNull);
  });

  testWidgets('photo slots become tappable once a status exists', (tester) async {
    await pumpScreen(tester, initial: _saved(AttendanceStatus.present));
    await tester.pumpAndSettle();

    expect(_inkWellIn(tester, const Key('checkin-photo')).onTap, isNotNull);
    expect(_inkWellIn(tester, const Key('belongings-photo')).onTap, isNotNull);
  });

  testWidgets('tapping an empty photo slot offers camera and gallery, no remove',
      (tester) async {
    await pumpScreen(tester, initial: _saved(AttendanceStatus.present));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('checkin-photo')));
    await tester.pumpAndSettle();

    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
    expect(find.text('Remove photo'), findsNothing);
  });

  testWidgets('tapping a filled photo slot also offers remove', (tester) async {
    // getSignedPhotoUrl never resolves, so the thumbnail spins forever and
    // pumpAndSettle would hang -- finite pumps let the sheet animate in.
    when(() => mockAttendance.getSignedPhotoUrl(any()))
        .thenAnswer((_) => Completer<String>().future);

    await pumpScreen(tester, initial: _withPhotos(photoPath: 'child-1/2026-09-01.jpg'));
    await tester.pump();

    await tester.tap(_slotTapTarget(const Key('checkin-photo')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
    expect(find.text('Remove photo'), findsOneWidget);
  });

  testWidgets('does not overflow the photo row on a narrow screen', (tester) async {
    // Regression guard for a RenderFlex overflow on the Belongings label --
    // the row's two halves must share the available width (Expanded plus
    // ellipsizing text) rather than each sizing to its own content.
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(tester, initial: _saved(AttendanceStatus.present));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('taking a check-in photo from the camera uploads and attaches it',
      (tester) async {
    final file = XFile('/tmp/shot.jpg');
    when(() => mockPhotoCapture.captureFromCamera()).thenAnswer((_) async => file);
    when(() => mockAttendance.uploadCheckInPhoto(
          childId: any(named: 'childId'),
          date: any(named: 'date'),
          photo: any(named: 'photo'),
        )).thenAnswer((_) async => 'child-1/2026-09-01.jpg');
    when(() => mockAttendance.attachCheckInPhoto(
          id: any(named: 'id'),
          photoPath: any(named: 'photoPath'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => _withPhotos(photoPath: 'child-1/2026-09-01.jpg'));
    when(() => mockAttendance.getSignedPhotoUrl(any()))
        .thenAnswer((_) => Completer<String>().future);

    Attendance? reported;
    await pumpScreen(
      tester,
      initial: _saved(AttendanceStatus.present),
      onChanged: (a) => reported = a,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('checkin-photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take a photo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // id is the attendance row's, not the child's -- easy to transpose.
    verify(() => mockAttendance.uploadCheckInPhoto(
          childId: 'child-1',
          date: '2026-09-01',
          photo: file,
        )).called(1);
    verify(() => mockAttendance.attachCheckInPhoto(
          id: 'att-1',
          photoPath: 'child-1/2026-09-01.jpg',
          actorUid: 'teacher-1',
        )).called(1);
    expect(reported?.photoPath, 'child-1/2026-09-01.jpg');
  });

  testWidgets('choosing a belongings photo from the gallery uploads and attaches it',
      (tester) async {
    final file = XFile('/tmp/bag.jpg');
    when(() => mockPhotoCapture.pickFromGallery()).thenAnswer((_) async => file);
    when(() => mockAttendance.uploadBelongingsPhoto(
          childId: any(named: 'childId'),
          date: any(named: 'date'),
          photo: any(named: 'photo'),
        )).thenAnswer((_) async => 'child-1/bag.jpg');
    when(() => mockAttendance.attachBelongingsPhoto(
          id: any(named: 'id'),
          belongingsPhotoPath: any(named: 'belongingsPhotoPath'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => _withPhotos(belongingsPhotoPath: 'child-1/bag.jpg'));
    when(() => mockAttendance.getSignedPhotoUrl(any()))
        .thenAnswer((_) => Completer<String>().future);

    await pumpScreen(tester, initial: _saved(AttendanceStatus.present));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('belongings-photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    verify(() => mockAttendance.attachBelongingsPhoto(
          id: 'att-1',
          belongingsPhotoPath: 'child-1/bag.jpg',
          actorUid: 'teacher-1',
        )).called(1);
  });

  testWidgets('removing a check-in photo clears it from the row', (tester) async {
    when(() => mockAttendance.getSignedPhotoUrl(any()))
        .thenAnswer((_) => Completer<String>().future);
    when(() => mockAttendance.removeCheckInPhoto(
          id: any(named: 'id'),
          photoPath: any(named: 'photoPath'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => _saved(AttendanceStatus.present));

    await pumpScreen(tester, initial: _withPhotos(photoPath: 'child-1/2026-09-01.jpg'));
    await tester.pump();

    await tester.tap(_slotTapTarget(const Key('checkin-photo')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Remove photo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    verify(() => mockAttendance.removeCheckInPhoto(
          id: 'att-1',
          photoPath: 'child-1/2026-09-01.jpg',
          actorUid: 'teacher-1',
        )).called(1);
  });

  testWidgets('shows an error message when the photo upload fails', (tester) async {
    // Pins the try/catch that had already been dropped once -- without a test,
    // a thrown upload vanishes into the error zone and the user sees nothing.
    when(() => mockPhotoCapture.captureFromCamera())
        .thenAnswer((_) async => XFile('/tmp/shot.jpg'));
    when(() => mockAttendance.uploadCheckInPhoto(
          childId: any(named: 'childId'),
          date: any(named: 'date'),
          photo: any(named: 'photo'),
        )).thenThrow(Exception('network down'));

    await pumpScreen(tester, initial: _saved(AttendanceStatus.present));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('checkin-photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take a photo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Could not save photo'), findsOneWidget);
  });

  testWidgets('cancelling the camera uploads nothing', (tester) async {
    when(() => mockPhotoCapture.captureFromCamera()).thenAnswer((_) async => null);

    await pumpScreen(tester, initial: _saved(AttendanceStatus.present));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('checkin-photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take a photo'));
    await tester.pumpAndSettle();

    verifyNever(() => mockAttendance.uploadCheckInPhoto(
          childId: any(named: 'childId'),
          date: any(named: 'date'),
          photo: any(named: 'photo'),
        ));
  });

  testWidgets('shows the thumbnail once a check-in photo is attached',
      (tester) async {
    when(() => mockAttendance.getSignedPhotoUrl(any()))
        .thenAnswer((_) => Completer<String>().future);

    await pumpScreen(tester, initial: _withPhotos(photoPath: 'child-1/2026-09-01.jpg'));
    await tester.pump();

    expect(find.byType(SignedPhotoThumbnail), findsOneWidget);
  });
}
