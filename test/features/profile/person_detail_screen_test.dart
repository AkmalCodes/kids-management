import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/auth/auth_service.dart';
import 'package:test_flutter/core/models/app_user.dart';
import 'package:test_flutter/core/services/profile_service.dart';
import 'package:test_flutter/features/profile/person_detail_screen.dart';

class MockProfileService extends Mock implements ProfileService {}

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

void main() {
  late MockProfileService mockProfile;

  setUp(() {
    mockProfile = MockProfileService();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    AppUser? currentUser,
    AppUser? person,
  }) => tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => Stream.value(currentUser ?? _director())),
            profileServiceProvider.overrideWithValue(mockProfile),
          ],
          child: MaterialApp(home: PersonDetailScreen(person: person ?? _teacher())),
        ),
      );

  testWidgets('pre-fills name, phone and shows the role', (tester) async {
    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'Ms. Smith'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '555-0100'), findsOneWidget);
    expect(find.text('Teacher'), findsOneWidget);
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

  testWidgets('editing your own profile uses the self-only update path', (tester) async {
    when(() => mockProfile.updateOwnDetails(
          name: any(named: 'name'),
          phone: any(named: 'phone'),
        )).thenAnswer((_) async => _teacher());

    // Current user is the same person being edited.
    await pumpScreen(tester, currentUser: _teacher(), person: _teacher());
    await tester.pumpAndSettle();

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

    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not save changes'), findsOneWidget);
  });
}
