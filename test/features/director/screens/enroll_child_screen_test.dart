import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/auth/auth_controller.dart';
import 'package:test_flutter/core/models/app_user.dart';
import 'package:test_flutter/core/models/child.dart';
import 'package:test_flutter/core/controllers/child_controller.dart';
import 'package:test_flutter/core/controllers/teacher_controller.dart';
import 'package:test_flutter/core/controllers/user_management_controller.dart';
import 'package:test_flutter/features/director/screens/enroll_child_screen.dart';

class MockChildController extends Mock implements ChildController {}

class MockTeacherController extends Mock implements TeacherController {}

class MockUserManagementController extends Mock implements UserManagementController {}

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

Child _savedChild() => Child(
  id: 'child-1',
  name: 'Alice',
  dob: DateTime(2023, 1, 1),
  centerId: 'center-1',
  className: '',
  teacherId: null,
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
    registerFallbackValue(FakeChild());
  });

  late MockChildController mockChildren;
  late MockTeacherController mockTeachers;
  late MockUserManagementController mockUserManagement;

  setUp(() {
    mockChildren = MockChildController();
    mockTeachers = MockTeacherController();
    mockUserManagement = MockUserManagementController();
    when(() => mockTeachers.fetchAll()).thenAnswer((_) async => []);
  });

  // The form has more fields than fit in the default 600px-tall test
  // surface, and ListView(children: [...]) still only mounts elements
  // within the viewport + cache extent (same lazy sliver mounting as
  // ListView.builder) -- widening the surface avoids needing to scroll to
  // reach fields near the bottom for every interaction.
  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(_director())),
          childControllerProvider.overrideWithValue(mockChildren),
          teacherControllerProvider.overrideWithValue(mockTeachers),
          userManagementControllerProvider.overrideWithValue(mockUserManagement),
        ],
        child: const MaterialApp(home: EnrollChildScreen()),
      ),
    );
  }

  testWidgets('blocks submit when required fields are missing', (tester) async {
    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enroll child & invite parent'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a name'), findsNWidgets(2));
    expect(find.text('Please enter an email'), findsOneWidget);
    verifyNever(() => mockChildren.createChild(any()));
  });

  testWidgets('enrolling creates the child then invites the parent with its id',
      (tester) async {
    when(() => mockChildren.createChild(any())).thenAnswer((_) async => _savedChild());
    when(() => mockUserManagement.inviteParent(
          email: any(named: 'email'),
          name: any(named: 'name'),
          childId: any(named: 'childId'),
          phone: any(named: 'phone'),
        )).thenAnswer((_) async {});

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, "Child's name"), 'Alice');
    await tester.enterText(find.widgetWithText(TextFormField, "Parent's name"), 'Jane Doe');
    await tester.enterText(
      find.widgetWithText(TextFormField, "Parent's email"),
      'jane@example.com',
    );
    await tester.tap(find.text('Enroll child & invite parent'));
    await tester.pumpAndSettle();

    final captured = verify(() => mockChildren.createChild(captureAny())).captured;
    final savedChild = captured.single as Child;
    expect(savedChild.name, 'Alice');
    expect(savedChild.centerId, 'center-1');
    expect(savedChild.createdBy, 'director-1');

    verify(() => mockUserManagement.inviteParent(
          email: 'jane@example.com',
          name: 'Jane Doe',
          childId: 'child-1',
          phone: '',
        )).called(1);
  });

  testWidgets('shows an error message when enrolling fails', (tester) async {
    when(() => mockChildren.createChild(any())).thenThrow(Exception('center_id violates'));

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, "Child's name"), 'Alice');
    await tester.enterText(find.widgetWithText(TextFormField, "Parent's name"), 'Jane Doe');
    await tester.enterText(
      find.widgetWithText(TextFormField, "Parent's email"),
      'jane@example.com',
    );
    await tester.tap(find.text('Enroll child & invite parent'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not enroll child'), findsOneWidget);
  });
}
