import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kawankecil/core/auth/auth_controller.dart';
import 'package:kawankecil/core/models/app_user.dart';
import 'package:kawankecil/core/controllers/photo_capture_controller.dart';
import 'package:kawankecil/core/controllers/profile_controller.dart';
import 'package:kawankecil/features/profile/change_password_screen.dart';
import 'package:kawankecil/features/profile/person_detail_screen.dart';
import 'package:kawankecil/features/profile/profile_screen.dart';

class MockAuthController extends Mock implements AuthController {}

class MockProfileController extends Mock implements ProfileController {}

class MockPhotoCaptureController extends Mock implements PhotoCaptureController {}

AppUser _user({String? avatarPath, String role = 'teacher'}) => AppUser(
  id: 'uid-1',
  role: role,
  name: 'Alice',
  phone: '',
  centerId: 'center-1',
  avatarPath: avatarPath,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

void main() {
  setUpAll(() {
    registerFallbackValue(XFile(''));
  });

  late MockAuthController mockAuth;
  late MockProfileController mockProfile;
  late MockPhotoCaptureController mockPhotoCapture;

  setUp(() {
    mockAuth = MockAuthController();
    mockProfile = MockProfileController();
    mockPhotoCapture = MockPhotoCaptureController();
    when(() => mockAuth.currentEmail).thenReturn('alice@example.com');
  });

  Future<void> pumpScreen(WidgetTester tester, {String? avatarPath, String role = 'teacher'}) async {
    // The default 800x600 test viewport is an artificial constraint, not a
    // real device limit -- the stack of profile actions (Profile details,
    // Change password, Sign out) runs past 600px and pushes the
    // lower buttons offscreen. A real phone screen is taller; give this
    // ListView room to actually fit rather than fight the test harness's
    // default with scroll gymnastics.
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWithValue(mockAuth),
          currentUserProvider.overrideWith((ref) => Stream.value(_user(avatarPath: avatarPath, role: role))),
          profileControllerProvider.overrideWithValue(mockProfile),
          photoCaptureControllerProvider.overrideWithValue(mockPhotoCapture),
        ],
        child: const MaterialApp(home: Scaffold(body: ProfileScreen())),
      ),
    );
  }

  testWidgets('shows the account name, email and role', (tester) async {
    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);
    expect(find.text('Teacher'), findsOneWidget);
  });

  testWidgets('shows a placeholder avatar when none is set', (tester) async {
    await pumpScreen(tester);
    await tester.pumpAndSettle();

    // No signed-url lookup happens without an avatar path.
    verifyNever(() => mockProfile.getSignedAvatarUrl(any()));
    expect(find.byIcon(Icons.person_outline), findsWidgets);
  });

  testWidgets('opening Change password navigates to ChangePasswordScreen', (tester) async {
    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();

    expect(find.byType(ChangePasswordScreen), findsOneWidget);
  });

  testWidgets('changing the photo uploads it and saves the path', (tester) async {
    final photo = XFile('');
    when(() => mockPhotoCapture.pickFromGallery()).thenAnswer((_) async => photo);
    when(() => mockProfile.uploadAvatar(userId: any(named: 'userId'), photo: any(named: 'photo')))
        .thenAnswer((_) async => 'uid-1/avatar.jpg');
    when(() => mockProfile.setAvatarPath(any())).thenAnswer((_) async {});

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Change photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();

    verify(() => mockProfile.uploadAvatar(userId: 'uid-1', photo: photo)).called(1);
    verify(() => mockProfile.setAvatarPath('uid-1/avatar.jpg')).called(1);
  });

  testWidgets('opening Profile details navigates to the person detail screen', (tester) async {
    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile details'));
    await tester.pumpAndSettle();

    final screen = tester.widget<PersonDetailScreen>(find.byType(PersonDetailScreen));
    expect(screen.person.id, 'uid-1');
  });

  testWidgets('signs out when Sign out is tapped', (tester) async {
    when(() => mockAuth.signOut()).thenAnswer((_) async {});

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    verify(() => mockAuth.signOut()).called(1);
  });
}
