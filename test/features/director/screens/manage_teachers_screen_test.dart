import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/models/app_user.dart';
import 'package:test_flutter/core/services/teacher_service.dart';
import 'package:test_flutter/core/services/user_management_service.dart';
import 'package:test_flutter/features/director/screens/manage_teachers_screen.dart';

class MockTeacherService extends Mock implements TeacherService {}

class MockUserManagementService extends Mock implements UserManagementService {}

AppUser _teacher(String id, String name) => AppUser(
  id: id,
  role: 'teacher',
  name: name,
  phone: '555-0100',
  centerId: 'center-1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

void main() {
  setUpAll(() {
    registerFallbackValue('');
  });

  late MockTeacherService mockTeachers;
  late MockUserManagementService mockUserManagement;

  setUp(() {
    mockTeachers = MockTeacherService();
    mockUserManagement = MockUserManagementService();
  });

  Future<void> pumpScreen(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          overrides: [
            teacherServiceProvider.overrideWithValue(mockTeachers),
            userManagementServiceProvider.overrideWithValue(mockUserManagement),
          ],
          child: const MaterialApp(home: ManageTeachersScreen()),
        ),
      );

  testWidgets('shows a message when there are no teachers yet', (tester) async {
    when(() => mockTeachers.fetchAll()).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('No teachers yet.'), findsOneWidget);
  });

  testWidgets('shows the teacher list', (tester) async {
    when(() => mockTeachers.fetchAll())
        .thenAnswer((_) async => [_teacher('teacher-1', 'Ms. Smith')]);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Ms. Smith'), findsOneWidget);
    expect(find.text('555-0100'), findsOneWidget);
  });

  testWidgets('inviting a teacher calls the service and refreshes the list', (tester) async {
    when(() => mockTeachers.fetchAll()).thenAnswer((_) async => []);
    when(() => mockUserManagement.inviteTeacher(
          email: any(named: 'email'),
          name: any(named: 'name'),
          phone: any(named: 'phone'),
        )).thenAnswer((_) async {});

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person_add_alt_1_outlined));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Ms. Smith');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'smith@example.com');
    await tester.tap(find.text('Invite'));
    await tester.pumpAndSettle();

    verify(() => mockUserManagement.inviteTeacher(
          email: 'smith@example.com',
          name: 'Ms. Smith',
          phone: '',
        )).called(1);
    expect(find.textContaining('Invite sent to smith@example.com'), findsOneWidget);
  });

  testWidgets('shows an error message when the invite fails', (tester) async {
    when(() => mockTeachers.fetchAll()).thenAnswer((_) async => []);
    when(() => mockUserManagement.inviteTeacher(
          email: any(named: 'email'),
          name: any(named: 'name'),
          phone: any(named: 'phone'),
        )).thenThrow(Exception('email already in use'));

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person_add_alt_1_outlined));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Ms. Smith');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'smith@example.com');
    await tester.tap(find.text('Invite'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not create teacher'), findsOneWidget);
  });
}
