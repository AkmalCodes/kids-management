import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/auth/auth_controller.dart';
import 'package:test_flutter/core/models/app_user.dart';
import 'package:test_flutter/core/models/attendance.dart';
import 'package:test_flutter/core/models/child.dart';
import 'package:test_flutter/core/controllers/attendance_controller.dart';
import 'package:test_flutter/core/controllers/child_controller.dart';
import 'package:test_flutter/core/controllers/photo_capture_controller.dart';
import 'package:test_flutter/features/teacher/screens/mark_attendance_screen.dart';
import 'package:test_flutter/shared/widgets/signed_photo_thumbnail.dart';

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

  testWidgets('shows roster and marks attendance on tap', (tester) async {
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
        date: '2026-07-23',
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

    expect(find.text('Alice'), findsOneWidget);

    // Cards start collapsed; expand this one before marking attendance.
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();

    verify(() => mockAttendance.markAttendance(
          childId: 'child-1',
          centerId: 'center-1',
          date: any(named: 'date'),
          status: AttendanceStatus.present,
          actorUid: 'teacher-1',
          existingId: null,
          notes: any(named: 'notes'),
        )).called(1);
  });

  InkWell inkWellFor(WidgetTester tester, Key key) => tester.widget<InkWell>(
        find.descendant(of: find.byKey(key), matching: find.byType(InkWell)),
      );

  Attendance buildAttendance({
    String? photoPath,
    String? belongingsPhotoPath,
  }) => Attendance(
    id: 'att-1',
    childId: 'child-1',
    centerId: 'center-1',
    date: '2026-07-23',
    status: AttendanceStatus.present,
    notes: '',
    photoPath: photoPath,
    belongingsPhotoPath: belongingsPhotoPath,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    createdBy: 'teacher-1',
    updatedBy: 'teacher-1',
  );

  testWidgets('photo slots are disabled until a status has been set for the day',
      (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1'))
        .thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(inkWellFor(tester, const Key('checkin-photo-child-1')).onTap, isNull);
    expect(inkWellFor(tester, const Key('belongings-photo-child-1')).onTap, isNull);
  });

  testWidgets('tapping an empty photo slot offers Take photo and Choose from gallery, no delete',
      (tester) async {
    final existing = buildAttendance();
    when(() => mockChildren.fetchForTeacher('teacher-1'))
        .thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => [existing]);

    await pumpScreen(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('checkin-photo-child-1')));
    await tester.pumpAndSettle();

    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
    expect(find.text('Delete photo'), findsNothing);
  });

  testWidgets('does not overflow the photo row on a narrow screen', (tester) async {
    final existing = buildAttendance();
    when(() => mockChildren.fetchForTeacher('teacher-1'))
        .thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => [existing]);

    // Regression guard for a RenderFlex overflow on the Belongings photo
    // label -- the photo row's two halves need to actually share the
    // available width (Expanded + ellipsizing text) rather than each
    // sizing to its own intrinsic content width.
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a filled photo slot offers Retake, Choose from gallery, and Delete',
      (tester) async {
    final existing = buildAttendance(photoPath: 'child-1/2026-07-23.jpg');
    when(() => mockChildren.fetchForTeacher('teacher-1'))
        .thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => [existing]);
    when(() => mockAttendance.getSignedPhotoUrl(any()))
        .thenAnswer((_) => Completer<String>().future);

    await pumpScreen(tester);
    await tester.pump();
    await tester.tap(find.text('Alice'));
    await tester.pump();

    // A never-resolving getSignedPhotoUrl (see above) leaves a spinner
    // animating forever, so pumpAndSettle would hang -- use a couple of
    // finite pumps to let the bottom sheet's entrance transition play out.
    await tester.tap(find.byKey(const Key('checkin-photo-child-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Retake photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
    expect(find.text('Delete photo'), findsOneWidget);
  });

  testWidgets('taking a check-in photo from the camera uploads and attaches it',
      (tester) async {
    final existing = buildAttendance();
    when(() => mockChildren.fetchForTeacher('teacher-1'))
        .thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => [existing]);
    final photo = XFile('');
    when(() => mockPhotoCapture.captureFromCamera()).thenAnswer((_) async => photo);
    when(() => mockAttendance.uploadCheckInPhoto(
          childId: any(named: 'childId'),
          date: any(named: 'date'),
          photo: any(named: 'photo'),
        )).thenAnswer((_) async => 'child-1/2026-07-23.jpg');
    when(() => mockAttendance.attachCheckInPhoto(
          id: any(named: 'id'),
          photoPath: any(named: 'photoPath'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => buildAttendance(photoPath: 'child-1/2026-07-23.jpg'));

    await pumpScreen(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('checkin-photo-child-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();

    verify(() => mockPhotoCapture.captureFromCamera()).called(1);
    verifyNever(() => mockPhotoCapture.pickFromGallery());
    verify(() => mockAttendance.uploadCheckInPhoto(
          childId: 'child-1',
          date: any(named: 'date'),
          photo: photo,
        )).called(1);
    verify(() => mockAttendance.attachCheckInPhoto(
          id: 'att-1',
          photoPath: 'child-1/2026-07-23.jpg',
          actorUid: 'teacher-1',
        )).called(1);
  });

  testWidgets('choosing a belongings photo from the gallery uploads and attaches it',
      (tester) async {
    final existing = buildAttendance();
    when(() => mockChildren.fetchForTeacher('teacher-1'))
        .thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => [existing]);
    final photo = XFile('');
    when(() => mockPhotoCapture.pickFromGallery()).thenAnswer((_) async => photo);
    when(() => mockAttendance.uploadBelongingsPhoto(
          childId: any(named: 'childId'),
          date: any(named: 'date'),
          photo: any(named: 'photo'),
        )).thenAnswer((_) async => 'child-1/2026-07-23-belongings.jpg');
    when(() => mockAttendance.attachBelongingsPhoto(
          id: any(named: 'id'),
          belongingsPhotoPath: any(named: 'belongingsPhotoPath'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer(
      (_) async => buildAttendance(belongingsPhotoPath: 'child-1/2026-07-23-belongings.jpg'),
    );

    await pumpScreen(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('belongings-photo-child-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();

    verify(() => mockPhotoCapture.pickFromGallery()).called(1);
    verifyNever(() => mockPhotoCapture.captureFromCamera());
    verify(() => mockAttendance.uploadBelongingsPhoto(
          childId: 'child-1',
          date: any(named: 'date'),
          photo: photo,
        )).called(1);
    verify(() => mockAttendance.attachBelongingsPhoto(
          id: 'att-1',
          belongingsPhotoPath: 'child-1/2026-07-23-belongings.jpg',
          actorUid: 'teacher-1',
        )).called(1);
  });

  testWidgets('deleting a check-in photo removes it from storage and clears the column',
      (tester) async {
    final existing = buildAttendance(photoPath: 'child-1/2026-07-23.jpg');
    when(() => mockChildren.fetchForTeacher('teacher-1'))
        .thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => [existing]);
    when(() => mockAttendance.getSignedPhotoUrl(any()))
        .thenAnswer((_) => Completer<String>().future);
    when(() => mockAttendance.removeCheckInPhoto(
          id: any(named: 'id'),
          photoPath: any(named: 'photoPath'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => buildAttendance());

    await pumpScreen(tester);
    await tester.pump();
    await tester.tap(find.text('Alice'));
    await tester.pump();

    // A never-resolving getSignedPhotoUrl (see above) leaves a spinner
    // animating forever, so pumpAndSettle would hang -- use finite pumps
    // throughout this test instead.
    await tester.tap(find.byKey(const Key('checkin-photo-child-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Delete photo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    verify(() => mockAttendance.removeCheckInPhoto(
          id: 'att-1',
          photoPath: 'child-1/2026-07-23.jpg',
          actorUid: 'teacher-1',
        )).called(1);
    expect(find.text('Take photo'), findsNothing);
  });

  testWidgets('shows an error message when the photo upload fails', (tester) async {
    final existing = buildAttendance();
    when(() => mockChildren.fetchForTeacher('teacher-1'))
        .thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => [existing]);
    when(() => mockPhotoCapture.captureFromCamera()).thenAnswer((_) async => XFile(''));
    when(() => mockAttendance.uploadCheckInPhoto(
          childId: any(named: 'childId'),
          date: any(named: 'date'),
          photo: any(named: 'photo'),
        )).thenThrow(Exception('bucket not found'));

    await pumpScreen(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('checkin-photo-child-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not save photo'), findsOneWidget);
  });

  testWidgets('canceling the camera does not upload or attach anything', (tester) async {
    final existing = buildAttendance();
    when(() => mockChildren.fetchForTeacher('teacher-1'))
        .thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => [existing]);
    when(() => mockPhotoCapture.captureFromCamera()).thenAnswer((_) async => null);

    await pumpScreen(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('checkin-photo-child-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();

    verifyNever(() => mockAttendance.uploadCheckInPhoto(
          childId: any(named: 'childId'),
          date: any(named: 'date'),
          photo: any(named: 'photo'),
        ));
    verifyNever(() => mockAttendance.attachCheckInPhoto(
          id: any(named: 'id'),
          photoPath: any(named: 'photoPath'),
          actorUid: any(named: 'actorUid'),
        ));
  });

  testWidgets('shows the thumbnail once a check-in photo has been attached', (tester) async {
    final existing = buildAttendance(photoPath: 'child-1/2026-07-23.jpg');
    when(() => mockChildren.fetchForTeacher('teacher-1'))
        .thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => [existing]);
    // Never resolves -- this test only cares that SignedPhotoThumbnail is
    // wired up with the right path, not that its image actually renders.
    // Letting the signed-URL future resolve would have CircleAvatar attempt
    // a real network image decode, which the test environment can't do.
    when(() => mockAttendance.getSignedPhotoUrl('child-1/2026-07-23.jpg'))
        .thenAnswer((_) => Completer<String>().future);

    await pumpScreen(tester);
    await tester.pump();

    // Collapsed, the leading avatar is the child's profile picture (absent
    // here), NOT the check-in photo -- so no check-in thumbnail yet.
    expect(find.byType(SignedPhotoThumbnail), findsNothing);

    // Expanding shows the check-in photo in its slot (a thumbnail replaces
    // the capture icon), wired to the stored path.
    await tester.tap(find.text('Alice'));
    await tester.pump();

    expect(find.byType(SignedPhotoThumbnail), findsOneWidget);
    final thumb = tester.widget<SignedPhotoThumbnail>(find.byType(SignedPhotoThumbnail));
    expect(thumb.photoPath, 'child-1/2026-07-23.jpg');
  });

  testWidgets('cards start collapsed showing only avatar, name, and status',
      (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1'))
        .thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Not marked'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(find.text('Not marked'), findsNothing);
    expect(find.byType(ChoiceChip), findsNWidgets(2));
  });

  testWidgets('only one card can be expanded at a time', (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1')).thenAnswer(
      (_) async => [
        _child(id: 'child-1', name: 'Alice'),
        _child(id: 'child-2', name: 'Bob'),
      ],
    );
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(find.byType(ChoiceChip), findsNWidgets(2));

    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();

    // Bob's card is now expanded, Alice's collapsed back down.
    expect(find.byType(ChoiceChip), findsNWidgets(2));
    expect(find.text('Not marked'), findsOneWidget);
  });

  testWidgets('typing a query in the search bar filters students by name',
      (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1')).thenAnswer(
      (_) async => [
        _child(id: 'child-1', name: 'Alice'),
        _child(id: 'child-2', name: 'Bob'),
      ],
    );
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ali');
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsNothing);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
  });
}
