import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kawankecil/core/auth/auth_controller.dart';
import 'package:kawankecil/core/models/app_user.dart';
import 'package:kawankecil/core/controllers/photo_capture_controller.dart';
import 'package:kawankecil/core/controllers/profile_controller.dart';
import 'package:kawankecil/features/profile/person_detail_screen.dart';

class MockProfileController extends Mock implements ProfileController {}

class MockPhotoCaptureController extends Mock implements PhotoCaptureController {}

AppUser _director() => AppUser(
  id: 'director-1',
  role: 'director',
  name: 'Director',
  phone: '',
  centerId: 'center-1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

AppUser _teacher() => AppUser(
  id: 'teacher-1',
  role: 'teacher',
  name: 'Ms. Smith',
  phone: '555-0100',
  centerId: 'center-1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

AppUser _teacherWithHr() => AppUser(
  id: 'teacher-1',
  role: 'teacher',
  name: 'Ms. Smith',
  phone: '555-0100',
  email: 'smith@example.com',
  address: '1 Oak St',
  dob: DateTime(1990, 3, 15),
  emergencyContactName: 'John Smith',
  emergencyContactPhone: '555-0199',
  centerId: 'center-1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

// Mirrors what TeacherController.fetchCoTeachers actually returns: identity
// only, no email in the projection and an empty phone.
AppUser _peerTeacher() => AppUser(
  id: 'teacher-2',
  role: 'teacher',
  name: 'Ms. Johnson',
  phone: '',
  centerId: 'center-1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

void main() {
  setUpAll(() {
    registerFallbackValue(XFile(''));
  });

  late MockProfileController mockProfile;
  late MockPhotoCaptureController mockPhotoCapture;

  setUp(() {
    mockProfile = MockProfileController();
    mockPhotoCapture = MockPhotoCaptureController();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    AppUser? currentUser,
    AppUser? person,
    bool readOnly = false,
  }) async {
    // Tall surface so the whole form (now with HR fields) fits and the Save
    // button is on-screen / tappable.
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(currentUser ?? _director())),
          profileControllerProvider.overrideWithValue(mockProfile),
          photoCaptureControllerProvider.overrideWithValue(mockPhotoCapture),
        ],
        child: MaterialApp(home: PersonDetailScreen(person: person ?? _teacher(), readOnly: readOnly)),
      ),
    );
  }

  // The screen opens read-only; tap the AppBar edit icon to reveal inputs.
  Future<void> enterEdit(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
  }

  testWidgets('opens read-only with values shown, then edit reveals inputs', (tester) async {
    await pumpScreen(tester);
    await tester.pumpAndSettle();

    // Read-only: values shown as text, no inputs, no Save button.
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Save changes'), findsNothing);
    expect(find.text('Ms. Smith'), findsWidgets); // AppBar title + name row
    expect(find.text('Teacher'), findsOneWidget);

    await enterEdit(tester);
    expect(find.widgetWithText(TextFormField, 'Ms. Smith'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '555-0100'), findsOneWidget);
  });

  testWidgets('saving writes the edited name and phone', (tester) async {
    when(() => mockProfile.updatePersonDetails(
          userId: any(named: 'userId'),
          name: any(named: 'name'),
          phone: any(named: 'phone'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => _teacher());

    await pumpScreen(tester);
    await tester.pumpAndSettle();
    await enterEdit(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Ms. Smith'), 'Ms. Jones');
    await tester.enterText(find.widgetWithText(TextFormField, '555-0100'), '555-9999');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    verify(() => mockProfile.updatePersonDetails(
          userId: 'teacher-1',
          name: 'Ms. Jones',
          phone: '555-9999',
          actorUid: 'director-1',
        )).called(1);
  });

  testWidgets('shows the read-only login email + HR values in view mode', (tester) async {
    await pumpScreen(tester, person: _teacherWithHr());
    await tester.pumpAndSettle();

    // View mode: email + HR values render as text (not inputs).
    expect(find.text('smith@example.com'), findsOneWidget);
    expect(find.text('Login email'), findsOneWidget);
    expect(find.text('1 Oak St'), findsOneWidget);
    expect(find.text('John Smith'), findsOneWidget);
    expect(find.textContaining('15/03/1990'), findsOneWidget);
  });

  testWidgets('tapping the email row copies it to the clipboard', (tester) async {
    // Capture what the app writes to the clipboard.
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await pumpScreen(tester, person: _teacherWithHr());
    await tester.pumpAndSettle();

    await tester.tap(find.text('smith@example.com'));
    await tester.pumpAndSettle();

    expect(copied, 'smith@example.com');
    expect(find.textContaining('Copied'), findsOneWidget);
  });

  testWidgets('saving writes the HR fields (address, dob, emergency contact)',
      (tester) async {
    when(() => mockProfile.updatePersonDetails(
          userId: any(named: 'userId'),
          name: any(named: 'name'),
          phone: any(named: 'phone'),
          address: any(named: 'address'),
          dob: any(named: 'dob'),
          emergencyContactName: any(named: 'emergencyContactName'),
          emergencyContactPhone: any(named: 'emergencyContactPhone'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => _teacherWithHr());

    await pumpScreen(tester, person: _teacherWithHr());
    await tester.pumpAndSettle();
    await enterEdit(tester);

    await tester.enterText(find.widgetWithText(TextFormField, '1 Oak St'), '2 Elm St');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    verify(() => mockProfile.updatePersonDetails(
          userId: 'teacher-1',
          name: 'Ms. Smith',
          phone: '555-0100',
          address: '2 Elm St',
          dob: '1990-03-15',
          emergencyContactName: 'John Smith',
          emergencyContactPhone: '555-0199',
          actorUid: 'director-1',
        )).called(1);
  });

  testWidgets('editing your own profile uses the self-only update path', (tester) async {
    when(() => mockProfile.updateOwnDetails(
          name: any(named: 'name'),
          phone: any(named: 'phone'),
        )).thenAnswer((_) async => _teacher());

    // Current user is the same person being edited.
    await pumpScreen(tester, currentUser: _teacher(), person: _teacher());
    await tester.pumpAndSettle();
    await enterEdit(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Ms. Smith'), 'Ms. Jones');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    verify(() => mockProfile.updateOwnDetails(name: 'Ms. Jones', phone: '555-0100')).called(1);
    verifyNever(() => mockProfile.updatePersonDetails(
          userId: any(named: 'userId'),
          name: any(named: 'name'),
          phone: any(named: 'phone'),
          actorUid: any(named: 'actorUid'),
        ));
  });

  testWidgets('blocks saving with an empty name', (tester) async {
    await pumpScreen(tester);
    await tester.pumpAndSettle();
    await enterEdit(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Ms. Smith'), '');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a name'), findsOneWidget);
    verifyNever(() => mockProfile.updatePersonDetails(
          userId: any(named: 'userId'),
          name: any(named: 'name'),
          phone: any(named: 'phone'),
          actorUid: any(named: 'actorUid'),
        ));
  });

  testWidgets('shows an error when saving fails', (tester) async {
    when(() => mockProfile.updatePersonDetails(
          userId: any(named: 'userId'),
          name: any(named: 'name'),
          phone: any(named: 'phone'),
          actorUid: any(named: 'actorUid'),
        )).thenThrow(Exception('rls denied'));

    await pumpScreen(tester);
    await tester.pumpAndSettle();
    await enterEdit(tester);

    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not save changes'), findsOneWidget);
  });

  testWidgets('a director changing another user\'s photo uses the director path',
      (tester) async {
    final photo = XFile('');
    when(() => mockPhotoCapture.pickFromGallery()).thenAnswer((_) async => photo);
    when(() => mockProfile.uploadAvatar(userId: any(named: 'userId'), photo: any(named: 'photo')))
        .thenAnswer((_) async => 'teacher-1/avatar.jpg');
    when(() => mockProfile.setAvatarPathFor(
          userId: any(named: 'userId'),
          path: any(named: 'path'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async {});

    await pumpScreen(tester); // director editing teacher-1
    await tester.pumpAndSettle();
    await enterEdit(tester);

    await tester.tap(find.text('Change photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();

    verify(() => mockProfile.uploadAvatar(userId: 'teacher-1', photo: photo)).called(1);
    verify(() => mockProfile.setAvatarPathFor(
          userId: 'teacher-1',
          path: 'teacher-1/avatar.jpg',
          actorUid: 'director-1',
        )).called(1);
    verifyNever(() => mockProfile.setAvatarPath(any()));
  });

  testWidgets('changing your own photo uses the self path', (tester) async {
    final photo = XFile('');
    when(() => mockPhotoCapture.captureFromCamera()).thenAnswer((_) async => photo);
    when(() => mockProfile.uploadAvatar(userId: any(named: 'userId'), photo: any(named: 'photo')))
        .thenAnswer((_) async => 'teacher-1/avatar.jpg');
    when(() => mockProfile.setAvatarPath(any())).thenAnswer((_) async {});

    await pumpScreen(tester, currentUser: _teacher(), person: _teacher());
    await tester.pumpAndSettle();
    await enterEdit(tester);

    await tester.tap(find.text('Change photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();

    verify(() => mockProfile.uploadAvatar(userId: 'teacher-1', photo: photo)).called(1);
    verify(() => mockProfile.setAvatarPath('teacher-1/avatar.jpg')).called(1);
    verifyNever(() => mockProfile.setAvatarPathFor(
          userId: any(named: 'userId'),
          path: any(named: 'path'),
          actorUid: any(named: 'actorUid'),
        ));
  });

  testWidgets('readOnly hides the Edit button and the "Not provided" rows',
      (tester) async {
    // A co-teacher-style AppUser: identity only, HR fields null.
    await pumpScreen(tester, person: _peerTeacher(), readOnly: true);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.text('Not provided'), findsNothing);
    expect(find.text(_peerTeacher().name), findsWidgets);
  });
}
