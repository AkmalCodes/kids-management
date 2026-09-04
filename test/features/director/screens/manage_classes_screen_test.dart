import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kids_management/core/auth/auth_controller.dart';
import 'package:kids_management/core/models/app_user.dart';
import 'package:kids_management/core/models/class_group.dart';
import 'package:kids_management/core/controllers/class_controller.dart';
import 'package:kids_management/core/controllers/teacher_controller.dart';
import 'package:kids_management/features/director/screens/class_detail_screen.dart';
import 'package:kids_management/features/director/screens/manage_classes_screen.dart';

class MockClassController extends Mock implements ClassController {}

class MockTeacherController extends Mock implements TeacherController {}

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

ClassGroup _class(String id, String name, {String? teacherId}) => ClassGroup(
  id: id,
  name: name,
  teacherIds: teacherId == null ? const [] : [teacherId],
  centerId: 'center-1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

void main() {
  setUpAll(() {
    registerFallbackValue(<String>[]);
  });

  late MockClassController mockClasses;
  late MockTeacherController mockTeachers;

  setUp(() {
    mockClasses = MockClassController();
    mockTeachers = MockTeacherController();
    when(() => mockTeachers.fetchAll()).thenAnswer((_) async => []);
    when(() => mockClasses.fetchAll()).thenAnswer((_) async => []);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(_director())),
          classControllerProvider.overrideWithValue(mockClasses),
          teacherControllerProvider.overrideWithValue(mockTeachers),
        ],
        child: const MaterialApp(home: ManageClassesScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows an empty message when there are no classes', (tester) async {
    await pumpScreen(tester);

    expect(find.text('No classes yet.'), findsOneWidget);
  });

  testWidgets('lists classes with their assigned teacher name', (tester) async {
    when(() => mockClasses.fetchAll()).thenAnswer(
      (_) async => [_class('class-1', 'Sunflowers', teacherId: 'teacher-1')],
    );
    when(() => mockTeachers.fetchAll())
        .thenAnswer((_) async => [_teacher('teacher-1', 'Ms. Rose')]);

    await pumpScreen(tester);

    expect(find.text('Sunflowers'), findsOneWidget);
    expect(find.text('Ms. Rose'), findsOneWidget);
  });

  testWidgets('shows a fallback subtitle when no teacher is assigned', (tester) async {
    when(() => mockClasses.fetchAll())
        .thenAnswer((_) async => [_class('class-1', 'Sunflowers')]);

    await pumpScreen(tester);

    expect(find.text('No teacher assigned'), findsOneWidget);
  });

  testWidgets('creating a class calls createClass and refreshes', (tester) async {
    when(() => mockClasses.createClass(
          name: any(named: 'name'),
          teacherIds: any(named: 'teacherIds'),
          centerId: any(named: 'centerId'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => _class('class-1', 'Sunflowers'));

    await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, ''), 'Sunflowers');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verify(() => mockClasses.createClass(
          name: 'Sunflowers',
          teacherIds: const [],
          centerId: 'center-1',
          actorUid: 'director-1',
        )).called(1);
    // Refresh re-reads the list.
    verify(() => mockClasses.fetchAll()).called(greaterThanOrEqualTo(2));
  });

  testWidgets('tapping a class opens the detail screen and saves via updateClass',
      (tester) async {
    when(() => mockClasses.fetchAll())
        .thenAnswer((_) async => [_class('class-1', 'Sunflowers')]);
    when(() => mockClasses.updateClass(
          id: any(named: 'id'),
          name: any(named: 'name'),
          teacherIds: any(named: 'teacherIds'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => _class('class-1', 'Tulips'));

    await pumpScreen(tester);

    await tester.tap(find.text('Sunflowers'));
    await tester.pumpAndSettle();

    // Now on the full ClassDetailScreen (not a dialog); it opens read-only.
    expect(find.byType(ClassDetailScreen), findsOneWidget);
    await tester.tap(find.byIcon(Icons.edit_outlined)); // enter edit mode
    await tester.pumpAndSettle();
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

  testWidgets('long-pressing a class then Delete calls deleteClass', (tester) async {
    when(() => mockClasses.fetchAll())
        .thenAnswer((_) async => [_class('class-1', 'Sunflowers')]);
    when(() => mockClasses.deleteClass(any())).thenAnswer((_) async {});

    await pumpScreen(tester);

    await tester.longPress(find.text('Sunflowers'));
    await tester.pumpAndSettle();
    // Bottom sheet -> Delete -> confirm dialog -> Delete.
    await tester.tap(find.widgetWithText(ListTile, 'Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    verify(() => mockClasses.deleteClass('class-1')).called(1);
  });
}
