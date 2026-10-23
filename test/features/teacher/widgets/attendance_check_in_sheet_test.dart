import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kawankecil/core/auth/auth_controller.dart';
import 'package:kawankecil/core/models/app_user.dart';
import 'package:kawankecil/core/models/attendance.dart';
import 'package:kawankecil/core/models/child.dart';
import 'package:kawankecil/core/controllers/attendance_controller.dart';
import 'package:kawankecil/core/controllers/photo_capture_controller.dart';
import 'package:kawankecil/features/teacher/widgets/attendance_check_in_sheet.dart';

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
      name: 'Alice Tan',
      dob: DateTime(2022, 1, 1),
      centerId: 'center-1',
      className: 'Bunga',
      teacherId: 'teacher-1',
      allergies: allergies,
      notes: '',
      enrolledAt: DateTime(2026),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      createdBy: 'director-1',
      updatedBy: 'director-1',
    );

Attendance _rec({
  AttendanceStatus status = AttendanceStatus.present,
  String notes = '',
  String? photoPath,
  String? belongingsPhotoPath,
}) =>
    Attendance(
      id: 'att-1',
      childId: 'child-1',
      centerId: 'center-1',
      date: '2026-10-23',
      status: status,
      notes: notes,
      photoPath: photoPath,
      belongingsPhotoPath: belongingsPhotoPath,
      createdAt: DateTime(2026, 10, 23, 7, 52),
      updatedAt: DateTime(2026),
      createdBy: 'teacher-1',
      updatedBy: 'teacher-1',
    );

void main() {
  setUpAll(() {
    registerFallbackValue(AttendanceStatus.present);
    registerFallbackValue(XFile(''));
  });

  late MockAttendanceController svc;
  late MockPhotoCaptureController cam;
  late List<Attendance> reported;
  Attendance? popped;

  setUp(() {
    svc = MockAttendanceController();
    cam = MockPhotoCaptureController();
    reported = [];
    popped = null;
    // Saved photos are shown via signed URLs; never resolve in tests (no
    // network), the photo area just stays a tint.
    when(() => svc.getSignedPhotoUrl(any())).thenAnswer((_) => Completer<String>().future);
  });

  void stubMark(Attendance Function(Invocation) answer) {
    when(() => svc.markAttendance(
          childId: any(named: 'childId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          status: any(named: 'status'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
          notes: any(named: 'notes'),
        )).thenAnswer((inv) async => answer(inv));
  }

  Future<void> open(WidgetTester tester, {Child? child, Attendance? existing, XFile? newPhoto}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_teacher())),
        attendanceControllerProvider.overrideWithValue(svc),
        photoCaptureControllerProvider.overrideWithValue(cam),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                popped = await showAttendanceCheckInSheet(
                  context,
                  child: child ?? _child(),
                  date: '2026-10-23',
                  existing: existing,
                  newPhoto: newPhoto,
                  onSaved: reported.add,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  testWidgets('shows allergies prominently when set', (tester) async {
    await open(tester, child: _child(allergies: 'Peanuts'));
    expect(find.text('Allergies: Peanuts'), findsOneWidget);
  });

  testWidgets('no allergy banner when there are none', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('allergy-warning')), findsNothing);
  });

  testWidgets('new child: button says "Check in <first name>", defaults to Present', (tester) async {
    stubMark((_) => _rec());
    await open(tester);
    expect(find.text('Check in Alice'), findsOneWidget);

    await tapVisible(tester, find.text('Check in Alice'));
    verify(() => svc.markAttendance(
          childId: 'child-1',
          centerId: 'center-1',
          date: '2026-10-23',
          status: AttendanceStatus.present,
          actorUid: 'teacher-1',
          existingId: null,
          notes: '',
        )).called(1);
    expect(popped?.id, 'att-1');
  });

  testWidgets('with a photo from the camera: mark, then upload, then attach', (tester) async {
    final shot = XFile('/tmp/shot.jpg');
    stubMark((_) => _rec());
    when(() => svc.uploadCheckInPhoto(
          childId: any(named: 'childId'),
          date: any(named: 'date'),
          photo: any(named: 'photo'),
        )).thenAnswer((_) async => 'child-1/2026-10-23.jpg');
    when(() => svc.attachCheckInPhoto(
          id: any(named: 'id'),
          photoPath: any(named: 'photoPath'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => _rec(photoPath: 'child-1/2026-10-23.jpg'));

    await open(tester, newPhoto: shot);
    await tapVisible(tester, find.text('Check in Alice'));

    verifyInOrder([
      () => svc.markAttendance(
            childId: 'child-1',
            centerId: 'center-1',
            date: '2026-10-23',
            status: AttendanceStatus.present,
            actorUid: 'teacher-1',
            existingId: null,
            notes: '',
          ),
      () => svc.uploadCheckInPhoto(childId: 'child-1', date: '2026-10-23', photo: shot),
      // The attendance row's id, not the child's -- easy to transpose.
      () => svc.attachCheckInPhoto(id: 'att-1', photoPath: 'child-1/2026-10-23.jpg', actorUid: 'teacher-1'),
    ]);
    expect(reported.last.photoPath, 'child-1/2026-10-23.jpg');
    expect(popped?.photoPath, 'child-1/2026-10-23.jpg');
  });

  testWidgets('a failed upload keeps the sheet open; retry updates the same row', (tester) async {
    final shot = XFile('/tmp/shot.jpg');
    stubMark((_) => _rec());
    var uploads = 0;
    when(() => svc.uploadCheckInPhoto(
          childId: any(named: 'childId'),
          date: any(named: 'date'),
          photo: any(named: 'photo'),
        )).thenAnswer((_) async {
      uploads++;
      if (uploads == 1) throw Exception('offline');
      return 'child-1/2026-10-23.jpg';
    });
    when(() => svc.attachCheckInPhoto(
          id: any(named: 'id'),
          photoPath: any(named: 'photoPath'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => _rec(photoPath: 'child-1/2026-10-23.jpg'));

    await open(tester, newPhoto: shot);
    await tapVisible(tester, find.text('Check in Alice'));

    expect(find.byType(AttendanceCheckInSheet), findsOneWidget);
    expect(find.textContaining('Could not save'), findsOneWidget);
    // The status DID save and was reported, so the grid shows it.
    expect(reported.single.id, 'att-1');

    await tapVisible(tester, find.text('Save'));
    // Second attempt updates the row created by the first, never inserts.
    verify(() => svc.markAttendance(
          childId: 'child-1',
          centerId: 'center-1',
          date: '2026-10-23',
          status: AttendanceStatus.present,
          actorUid: 'teacher-1',
          existingId: 'att-1',
          notes: '',
        )).called(1);
    expect(popped?.photoPath, 'child-1/2026-10-23.jpg');
  });

  testWidgets('existing record: Save keeps its id, status can change, note is kept', (tester) async {
    stubMark((_) => _rec(status: AttendanceStatus.late, notes: 'Ate well'));
    await open(tester, existing: _rec(notes: 'Ate well'));

    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Ate well'), findsOneWidget);
    await tester.tap(find.byKey(const Key('status-late')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Save'));

    verify(() => svc.markAttendance(
          childId: 'child-1',
          centerId: 'center-1',
          date: '2026-10-23',
          status: AttendanceStatus.late,
          actorUid: 'teacher-1',
          existingId: 'att-1',
          notes: 'Ate well',
        )).called(1);
  });

  testWidgets('Add a note reveals a field and the text is saved', (tester) async {
    stubMark((_) => _rec(notes: 'Bring a hat'));
    await open(tester);
    await tapVisible(tester, find.byKey(const Key('add-note')));
    await tester.enterText(find.byKey(const Key('attendance-note')), 'Bring a hat');
    await tapVisible(tester, find.text('Check in Alice'));

    verify(() => svc.markAttendance(
          childId: any(named: 'childId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          status: any(named: 'status'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
          notes: 'Bring a hat',
        )).called(1);
  });

  testWidgets('Remove on a saved photo removes it when saving', (tester) async {
    stubMark((_) => _rec(photoPath: 'child-1/old.jpg'));
    when(() => svc.removeCheckInPhoto(
          id: any(named: 'id'),
          photoPath: any(named: 'photoPath'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => _rec());

    await open(tester, existing: _rec(photoPath: 'child-1/old.jpg'));
    await tapVisible(tester, find.text('Remove'));
    // Nothing removed until Save.
    verifyNever(() => svc.removeCheckInPhoto(
          id: any(named: 'id'),
          photoPath: any(named: 'photoPath'),
          actorUid: any(named: 'actorUid'),
        ));
    await tapVisible(tester, find.text('Save'));

    verify(() => svc.removeCheckInPhoto(id: 'att-1', photoPath: 'child-1/old.jpg', actorUid: 'teacher-1'))
        .called(1);
    expect(popped?.photoPath, isNull);
  });

  testWidgets('belongings from the gallery is uploaded and attached on save', (tester) async {
    final pic = XFile('/tmp/bag.jpg');
    when(() => cam.pickFromGallery()).thenAnswer((_) async => pic);
    stubMark((_) => _rec());
    when(() => svc.uploadBelongingsPhoto(
          childId: any(named: 'childId'),
          date: any(named: 'date'),
          photo: any(named: 'photo'),
        )).thenAnswer((_) async => 'child-1/2026-10-23-belongings.jpg');
    when(() => svc.attachBelongingsPhoto(
          id: any(named: 'id'),
          belongingsPhotoPath: any(named: 'belongingsPhotoPath'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => _rec(belongingsPhotoPath: 'child-1/2026-10-23-belongings.jpg'));

    await open(tester);
    await tapVisible(tester, find.byTooltip('Belongings from gallery'));
    await tapVisible(tester, find.text('Check in Alice'));

    verify(() => svc.uploadBelongingsPhoto(childId: 'child-1', date: '2026-10-23', photo: pic)).called(1);
    verify(() => svc.attachBelongingsPhoto(
          id: 'att-1',
          belongingsPhotoPath: 'child-1/2026-10-23-belongings.jpg',
          actorUid: 'teacher-1',
        )).called(1);
  });

  testWidgets('no photo yet: "Take check-in photo" opens the camera', (tester) async {
    when(() => cam.captureFromCamera()).thenAnswer((_) async => XFile('/tmp/a.jpg'));
    await open(tester);
    await tapVisible(tester, find.text('Take check-in photo'));
    verify(() => cam.captureFromCamera()).called(1);
    expect(find.text('Retake'), findsOneWidget); // now a photo is staged
  });

  testWidgets('closing the sheet writes nothing', (tester) async {
    await open(tester, newPhoto: XFile('/tmp/shot.jpg'));
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    verifyNever(() => svc.markAttendance(
          childId: any(named: 'childId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          status: any(named: 'status'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
          notes: any(named: 'notes'),
        ));
    expect(popped, isNull);
  });

  testWidgets('fits a 360px-wide phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await open(tester, child: _child(allergies: 'Peanuts, eggs and shellfish'), existing: _rec(photoPath: 'p.jpg'));
    expect(tester.takeException(), isNull);
  });
}
