import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kawankecil/core/auth/auth_controller.dart';
import 'package:kawankecil/features/profile/change_password_screen.dart';

class MockAuthController extends Mock implements AuthController {}

void main() {
  late MockAuthController mockAuth;

  setUp(() {
    mockAuth = MockAuthController();
  });

  Future<void> pumpScreen(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          overrides: [authControllerProvider.overrideWithValue(mockAuth)],
          child: const MaterialApp(home: ChangePasswordScreen()),
        ),
      );

  testWidgets('blocks a too-short password', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'New password'), '123');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), '123');
    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();

    expect(find.text('At least 6 characters'), findsOneWidget);
    verifyNever(() => mockAuth.updatePassword(any()));
  });

  testWidgets('blocks mismatched confirmation', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'New password'), 'secret123');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), 'nope');
    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();

    expect(find.text('Passwords do not match'), findsOneWidget);
    verifyNever(() => mockAuth.updatePassword(any()));
  });

  testWidgets('updates the password on save', (tester) async {
    when(() => mockAuth.updatePassword(any())).thenAnswer((_) async {});

    await pumpScreen(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'New password'), 'secret123');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), 'secret123');
    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();

    verify(() => mockAuth.updatePassword('secret123')).called(1);
  });

  testWidgets('shows an error message when the update fails', (tester) async {
    when(() => mockAuth.updatePassword(any())).thenThrow(Exception('weak'));

    await pumpScreen(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'New password'), 'secret123');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), 'secret123');
    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not update password'), findsOneWidget);
  });
}
