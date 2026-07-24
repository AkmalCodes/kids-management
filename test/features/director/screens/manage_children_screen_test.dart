import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/auth/auth_service.dart';
import 'package:test_flutter/core/models/app_user.dart';
import 'package:test_flutter/core/models/child.dart';
import 'package:test_flutter/core/services/child_service.dart';
import 'package:test_flutter/core/services/teacher_service.dart';
import 'package:test_flutter/core/services/user_management_service.dart';
import 'package:test_flutter/features/director/screens/child_detail_screen.dart';
import 'package:test_flutter/features/director/screens/enroll_child_screen.dart';
import 'package:test_flutter/features/director/screens/manage_children_screen.dart';

class MockChildService extends Mock implements ChildService {}

class MockTeacherService extends Mock implements TeacherService {}

class MockUserManagementService extends Mock implements UserManagementService {}

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

Child _child(String id, String name, {String className = ''}) => Child(
  id: id,
  name: name,
  dob: DateTime(2022, 1, 1),
  centerId: 'center-1',
  className: className,
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
  late MockChildService mockChildren;
  late MockTeacherService mockTeachers;
  late MockUserManagementService mockUserManagement;

  setUp(() {
    mockChildren = MockChildService();
    mockTeachers = MockTeacherService();
    mockUserManagement = MockUserManagementService();
    when(() => mockTeachers.fetchAll()).thenAnswer((_) async => []);
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
          userManagementServiceProvider.overrideWithValue(mockUserManagement),
        ],
        child: const MaterialApp(home: ManageChildrenScreen()),
      ),
    );
  }

  testWidgets('shows a message when no children are enrolled', (tester) async {
    when(() => mockChildren.fetchAll()).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('No children enrolled yet.'), findsOneWidget);
  });

  testWidgets('shows the child list', (tester) async {
    when(() => mockChildren.fetchAll())
        .thenAnswer((_) async => [_child('child-1', 'Alice', className: 'Class A')]);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Class A'), findsOneWidget);
  });

  testWidgets('inviting a parent for an existing child calls the service', (tester) async {
    when(() => mockChildren.fetchAll()).thenAnswer((_) async => [_child('child-1', 'Alice')]);
    when(() => mockUserManagement.inviteParent(
          email: any(named: 'email'),
          name: any(named: 'name'),
          childId: any(named: 'childId'),
          phone: any(named: 'phone'),
        )).thenAnswer((_) async {});

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person_add_alt_1_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Invite a parent for Alice'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Jane Doe');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'jane@example.com');
    await tester.tap(find.text('Invite'));
    await tester.pumpAndSettle();

    verify(() => mockUserManagement.inviteParent(
          email: 'jane@example.com',
          name: 'Jane Doe',
          childId: 'child-1',
          phone: '',
        )).called(1);
    expect(find.textContaining('Invite sent to jane@example.com'), findsOneWidget);
  });

  testWidgets('shows an error message when inviting a parent fails', (tester) async {
    when(() => mockChildren.fetchAll()).thenAnswer((_) async => [_child('child-1', 'Alice')]);
    when(() => mockUserManagement.inviteParent(
          email: any(named: 'email'),
          name: any(named: 'name'),
          childId: any(named: 'childId'),
          phone: any(named: 'phone'),
        )).thenThrow(Exception('email already invited'));

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person_add_alt_1_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Jane Doe');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'jane@example.com');
    await tester.tap(find.text('Invite'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not invite parent'), findsOneWidget);
  });

  testWidgets('tapping the FAB opens the enroll child screen', (tester) async {
    when(() => mockChildren.fetchAll()).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.byType(EnrollChildScreen), findsOneWidget);
  });

  testWidgets('tapping a child row opens their detail screen', (tester) async {
    when(() => mockChildren.fetchAll()).thenAnswer((_) async => [_child('child-1', 'Alice')]);
    when(() => mockTeachers.fetchAll()).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    final screen = tester.widget<ChildDetailScreen>(find.byType(ChildDetailScreen));
    expect(screen.child.id, 'child-1');
  });
}
