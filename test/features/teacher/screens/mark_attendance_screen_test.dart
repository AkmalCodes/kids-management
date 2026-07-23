import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/auth/auth_service.dart';
import 'package:test_flutter/core/models/app_user.dart';
import 'package:test_flutter/core/models/attendance.dart';
import 'package:test_flutter/core/models/child.dart';
import 'package:test_flutter/core/services/attendance_service.dart';
import 'package:test_flutter/core/services/child_service.dart';
import 'package:test_flutter/core/services/photo_capture_service.dart';
import 'package:test_flutter/features/teacher/screens/mark_attendance_screen.dart';
import 'package:test_flutter/shared/widgets/signed_photo_thumbnail.dart';

class MockChildService extends Mock implements ChildService {}

class MockAttendanceService extends Mock implements AttendanceService {}

class MockPhotoCaptureService extends Mock implements PhotoCaptureService {}

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
  roomId: '',
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

  late MockChildService mockChildren;
  late MockAttendanceService mockAttendance;
  late MockPhotoCaptureService mockPhotoCapture;

  setUp(() {
    mockChildren = MockChildService();
    mockAttendance = MockAttendanceService();
    mockPhotoCapture = MockPhotoCaptureService();
  });

  Future<void> pumpScreen(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => Stream.value(_teacher())),
            childServiceProvider.overrideWithValue(mockChildren),
            attendanceServiceProvider.overrideWithValue(mockAttendance),
            photoCaptureServiceProvider.overrideWithValue(mockPhotoCapture),
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

  testWidgets('photo buttons are disabled until a status has been set for the day',
      (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1'))
        .thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    final checkInButton = tester.widget<IconButton>(find.byKey(const Key('checkin-photo-child-1')));
    final belongingsButton =
        tester.widget<IconButton>(find.byKey(const Key('belongings-photo-child-1')));
    expect(checkInButton.onPressed, isNull);
    expect(belongingsButton.onPressed, isNull);
  });

  testWidgets('capturing a check-in photo uploads and attaches it once a status exists',
      (tester) async {
    final existing = Attendance(
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
    );
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
        )).thenAnswer(
      (_) async => Attendance(
        id: 'att-1',
        childId: 'child-1',
        centerId: 'center-1',
        date: '2026-07-23',
        status: AttendanceStatus.present,
        notes: '',
        photoPath: 'child-1/2026-07-23.jpg',
        belongingsPhotoPath: null,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        createdBy: 'teacher-1',
        updatedBy: 'teacher-1',
      ),
    );

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    final checkInButton = tester.widget<IconButton>(find.byKey(const Key('checkin-photo-child-1')));
    expect(checkInButton.onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('checkin-photo-child-1')));
    await tester.pumpAndSettle();

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

  testWidgets('capturing a belongings photo uploads and attaches it once a status exists',
      (tester) async {
    final existing = Attendance(
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
    );
    when(() => mockChildren.fetchForTeacher('teacher-1'))
        .thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => [existing]);
    final photo = XFile('');
    when(() => mockPhotoCapture.captureFromCamera()).thenAnswer((_) async => photo);
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
      (_) async => Attendance(
        id: 'att-1',
        childId: 'child-1',
        centerId: 'center-1',
        date: '2026-07-23',
        status: AttendanceStatus.present,
        notes: '',
        photoPath: null,
        belongingsPhotoPath: 'child-1/2026-07-23-belongings.jpg',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        createdBy: 'teacher-1',
        updatedBy: 'teacher-1',
      ),
    );

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('belongings-photo-child-1')));
    await tester.pumpAndSettle();

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

  testWidgets('shows an error message when the photo upload fails', (tester) async {
    final existing = Attendance(
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
    );
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

    expect(find.textContaining('Could not save photo'), findsOneWidget);
  });

  testWidgets('canceling the camera does not upload or attach anything', (tester) async {
    final existing = Attendance(
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
    );
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
    final existing = Attendance(
      id: 'att-1',
      childId: 'child-1',
      centerId: 'center-1',
      date: '2026-07-23',
      status: AttendanceStatus.present,
      notes: '',
      photoPath: 'child-1/2026-07-23.jpg',
      belongingsPhotoPath: null,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      createdBy: 'teacher-1',
      updatedBy: 'teacher-1',
    );
    when(() => mockChildren.fetchForTeacher('teacher-1'))
        .thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => [existing]);
    when(() => mockAttendance.getSignedPhotoUrl('child-1/2026-07-23.jpg'))
        .thenAnswer((_) async => 'https://example.supabase.co/signed/child-1/2026-07-23.jpg');

    await pumpScreen(tester);
    // Deliberately single pumps (not pumpAndSettle): once the signed URL
    // resolves, CircleAvatar would attempt a real network image decode in
    // the test environment and throw. Checking the thumbnail's photoPath
    // prop is enough to confirm it was wired up correctly.
    await tester.pump();
    await tester.pump();

    // The collapsed card's leading avatar already reuses the check-in photo.
    final avatar = tester.widget<SignedPhotoThumbnail>(find.byType(SignedPhotoThumbnail).first);
    expect(avatar.photoPath, 'child-1/2026-07-23.jpg');

    // Expanding shows the same photo in the check-in slot instead of the
    // capture button.
    await tester.tap(find.text('Alice'));
    await tester.pump();

    expect(find.byKey(const Key('checkin-photo-child-1')), findsNothing);
    expect(find.byType(SignedPhotoThumbnail), findsNWidgets(2));
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
