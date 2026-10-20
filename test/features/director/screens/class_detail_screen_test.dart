import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kawankecil/core/auth/auth_controller.dart';
import 'package:kawankecil/core/models/app_user.dart';
import 'package:kawankecil/core/models/class_group.dart';
import 'package:kawankecil/core/controllers/class_controller.dart';
import 'package:kawankecil/core/controllers/photo_capture_controller.dart';
import 'package:kawankecil/core/controllers/teacher_controller.dart';
import 'package:kawankecil/features/director/screens/class_detail_screen.dart';
import 'package:kawankecil/shared/widgets/teacher_multi_select.dart';

class MockClassController extends Mock implements ClassController {}

class MockTeacherController extends Mock implements TeacherController {}

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

AppUser _teacher(String id, String name) => AppUser(
  id: id,
  role: 'teacher',
  name: name,
  phone: '',
  centerId: 'center-1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

ClassGroup _class() => ClassGroup(
  id: 'class-1',
  name: 'Sunflowers',
  teacherIds: const [],
  centerId: 'center-1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

void main() {
  setUpAll(() {
    registerFallbackValue(XFile(''));
    registerFallbackValue(<String>[]);
  });

  late MockClassController mockClasses;
  late MockTeacherController mockTeachers;
  late MockPhotoCaptureController mockPhotoCapture;

  setUp(() {
    mockClasses = MockClassController();
    mockTeachers = MockTeacherController();
    mockPhotoCapture = MockPhotoCaptureController();
    when(() => mockTeachers.fetchAll())
        .thenAnswer((_) async => [_teacher('teacher-1', 'Ms. Rose')]);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(_director())),
          classControllerProvider.overrideWithValue(mockClasses),
          teacherControllerProvider.overrideWithValue(mockTeachers),
          photoCaptureControllerProvider.overrideWithValue(mockPhotoCapture),
        ],
        child: MaterialApp(home: ClassDetailScreen(classGroup: _class())),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The screen opens read-only; tap the AppBar edit icon to reveal inputs.
  Future<void> enterEdit(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
  }

  testWidgets('opens read-only, then edit reveals the pre-filled name', (tester) async {
    await pumpScreen(tester);

    // Read-only: no input field yet, no Save button.
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Save changes'), findsNothing);

    await enterEdit(tester);
    expect(find.widgetWithText(TextFormField, 'Sunflowers'), findsOneWidget);
  });

  testWidgets('saving with a teacher picked writes teacherIds via updateClass',
      (tester) async {
    when(() => mockClasses.updateClass(
          id: any(named: 'id'),
          name: any(named: 'name'),
          teacherIds: any(named: 'teacherIds'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => _class());

    await pumpScreen(tester);
    await enterEdit(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Sunflowers'), 'Tulips');

    // Drive the real TeacherMultiSelect: open its "Add teacher" dropdown and
    // pick Ms. Rose (the one teacher fetchAll() returns).
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ms. Rose').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    verify(() => mockClasses.updateClass(
          id: 'class-1',
          name: 'Tulips',
          teacherIds: ['teacher-1'],
          actorUid: 'director-1',
        )).called(1);
  });

  testWidgets('saving with no teacher selected writes teacherIds: const []',
      (tester) async {
    when(() => mockClasses.updateClass(
          id: any(named: 'id'),
          name: any(named: 'name'),
          teacherIds: any(named: 'teacherIds'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => _class());

    await pumpScreen(tester);
    await enterEdit(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Sunflowers'), 'Tulips');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    verify(() => mockClasses.updateClass(
          id: 'class-1',
          name: 'Tulips',
          teacherIds: const [],
          actorUid: 'director-1',
        )).called(1);
  });

  testWidgets(
      'teacher fetch failure shows an inline error and no TeacherMultiSelect',
      (tester) async {
    // Override the setUp default: fetchAll() rejects.
    when(() => mockTeachers.fetchAll())
        .thenAnswer((_) async => throw Exception('network down'));

    await pumpScreen(tester);
    await enterEdit(tester);

    // Both modes: a short inline message instead of "…" / "Unknown teacher".
    expect(find.text("Couldn't load teachers"), findsOneWidget);
    // Edit mode must NOT render the multi-select against an empty list -- a
    // director could otherwise delete a chip they can't identify.
    expect(find.byType(TeacherMultiSelect), findsNothing);
  });

  testWidgets('changing the photo uploads it and writes the class avatar path',
      (tester) async {
    final photo = XFile('');
    when(() => mockPhotoCapture.pickFromGallery()).thenAnswer((_) async => photo);
    when(() => mockClasses.uploadClassAvatar(
          classId: any(named: 'classId'),
          photo: any(named: 'photo'),
        )).thenAnswer((_) async => 'class-1/avatar.jpg');
    when(() => mockClasses.setClassAvatarPath(
          classId: any(named: 'classId'),
          path: any(named: 'path'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async {});

    await pumpScreen(tester);
    await enterEdit(tester);

    await tester.tap(find.text('Change photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();

    verify(() => mockClasses.uploadClassAvatar(classId: 'class-1', photo: photo)).called(1);
    verify(() => mockClasses.setClassAvatarPath(
          classId: 'class-1',
          path: 'class-1/avatar.jpg',
          actorUid: 'director-1',
        )).called(1);
  });
}
