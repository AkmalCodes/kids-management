import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/auth/auth_service.dart';
import 'package:test_flutter/core/models/app_user.dart';
import 'package:test_flutter/core/models/child.dart';
import 'package:test_flutter/core/services/child_service.dart';
import 'package:test_flutter/core/services/class_service.dart';
import 'package:test_flutter/core/services/photo_capture_service.dart';
import 'package:test_flutter/core/services/teacher_service.dart';
import 'package:test_flutter/features/director/screens/child_detail_screen.dart';

class MockChildService extends Mock implements ChildService {}

class MockTeacherService extends Mock implements TeacherService {}

class MockClassService extends Mock implements ClassService {}

class MockPhotoCaptureService extends Mock implements PhotoCaptureService {}

class FakeChild extends Fake implements Child {}

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

Child _child() => Child(
  id: 'child-1',
  name: 'Alice',
  dob: DateTime(2022, 6, 1),
  centerId: 'center-1',
  className: 'Class A',
  teacherId: null,
  allergies: 'Peanuts',
  notes: '',
  enrolledAt: DateTime(2026),
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

void main() {
  setUpAll(() {
    registerFallbackValue(FakeChild());
    registerFallbackValue(XFile(''));
  });

  late MockChildService mockChildren;
  late MockTeacherService mockTeachers;
  late MockClassService mockClasses;
  late MockPhotoCaptureService mockPhotoCapture;

  setUp(() {
    mockChildren = MockChildService();
    mockTeachers = MockTeacherService();
    mockClasses = MockClassService();
    mockPhotoCapture = MockPhotoCaptureService();
    when(() => mockTeachers.fetchAll()).thenAnswer((_) async => []);
    when(() => mockClasses.fetchAll()).thenAnswer((_) async => []);
    when(() => mockChildren.fetchParentsForChild(any())).thenAnswer((_) async => []);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(_director())),
          childServiceProvider.overrideWithValue(mockChildren),
          teacherServiceProvider.overrideWithValue(mockTeachers),
          classServiceProvider.overrideWithValue(mockClasses),
          photoCaptureServiceProvider.overrideWithValue(mockPhotoCapture),
        ],
        child: MaterialApp(home: ChildDetailScreen(child: _child())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('pre-fills the existing details and shows the age', (tester) async {
    await pumpScreen(tester);

    expect(find.widgetWithText(TextFormField, 'Alice'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Peanuts'), findsOneWidget);
    // Born 2022-06-01; current test date is 2026, so age is 3 or 4.
    expect(find.textContaining('Age '), findsOneWidget);
  });

  testWidgets('saving writes the edited fields via updateChild', (tester) async {
    when(() => mockChildren.updateChild(any())).thenAnswer((_) async => _child());

    await pumpScreen(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Alice'), 'Alice B');
    await tester.enterText(find.widgetWithText(TextFormField, 'Peanuts'), 'None');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final saved = verify(() => mockChildren.updateChild(captureAny())).captured.single as Child;
    expect(saved.id, 'child-1');
    expect(saved.name, 'Alice B');
    expect(saved.allergies, 'None');
    expect(saved.updatedBy, 'director-1');
  });

  testWidgets('shows an error and does not pop when saving fails', (tester) async {
    when(() => mockChildren.updateChild(any())).thenThrow(Exception('rls denied'));

    await pumpScreen(tester);

    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not save changes'), findsOneWidget);
    expect(find.byType(ChildDetailScreen), findsOneWidget);
  });

  testWidgets('changing the photo uploads it and saves the child avatar path',
      (tester) async {
    final photo = XFile('');
    when(() => mockPhotoCapture.pickFromGallery()).thenAnswer((_) async => photo);
    when(() => mockChildren.uploadChildAvatar(
          childId: any(named: 'childId'),
          photo: any(named: 'photo'),
        )).thenAnswer((_) async => 'child-1/avatar.jpg');
    when(() => mockChildren.setChildAvatarPath(
          childId: any(named: 'childId'),
          path: any(named: 'path'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async {});

    await pumpScreen(tester);

    await tester.tap(find.text('Change photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();

    verify(() => mockChildren.uploadChildAvatar(childId: 'child-1', photo: photo)).called(1);
    verify(() => mockChildren.setChildAvatarPath(
          childId: 'child-1',
          path: 'child-1/avatar.jpg',
          actorUid: 'director-1',
        )).called(1);
  });

  testWidgets('shows the linked parents with their names and emails', (tester) async {
    when(() => mockChildren.fetchParentsForChild('child-1')).thenAnswer(
      (_) async => [
        AppUser(
          id: 'parent-1',
          role: 'parent',
          name: 'Jane Doe',
          phone: '',
          email: 'jane@example.com',
          centerId: 'center-1',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          createdBy: 'director-1',
          updatedBy: 'director-1',
        ),
      ],
    );

    await pumpScreen(tester);

    expect(find.text('Parents'), findsOneWidget);
    expect(find.text('Jane Doe'), findsOneWidget);
    expect(find.text('jane@example.com'), findsOneWidget);
  });

  testWidgets('shows a message when no parents are linked', (tester) async {
    when(() => mockChildren.fetchParentsForChild('child-1')).thenAnswer((_) async => []);

    await pumpScreen(tester);

    expect(find.text('No parents linked yet.'), findsOneWidget);
  });
}
