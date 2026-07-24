import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/auth/auth_service.dart';
import 'package:test_flutter/features/auth/set_password_screen.dart';

class MockAuthService extends Mock implements AuthService {}

void main() {
  late MockAuthService mockAuth;

  setUp(() {
    mockAuth = MockAuthService();
  });

  Future<void> pumpScreen(WidgetTester tester, {bool clearFlag = true}) => tester.pumpWidget(
        ProviderScope(
          overrides: [authServiceProvider.overrideWithValue(mockAuth)],
          child: MaterialApp(
            home: SetPasswordScreen(clearMustSetPasswordFlag: clearFlag),
          ),
        ),
      );

  testWidgets('blocks a too-short password', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'New password'), '123');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), '123');
    await tester.tap(find.text('Save password'));
    await tester.pumpAndSettle();

    expect(find.text('At least 6 characters'), findsOneWidget);
    verifyNever(() => mockAuth.updatePassword(any()));
  });

  testWidgets('blocks when confirmation does not match', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'New password'), 'secret123');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), 'different');
    await tester.tap(find.text('Save password'));
    await tester.pumpAndSettle();

    expect(find.text('Passwords do not match'), findsOneWidget);
    verifyNever(() => mockAuth.updatePassword(any()));
  });

  testWidgets('updates the password and clears the flag on save', (tester) async {
    when(() => mockAuth.updatePassword(any())).thenAnswer((_) async {});
    when(() => mockAuth.completePasswordSetup()).thenAnswer((_) async {});

    await pumpScreen(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'New password'), 'secret123');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), 'secret123');
    await tester.tap(find.text('Save password'));
    // Finite pumps (not pumpAndSettle): on success the button shows a
    // spinner that in this isolated screen (no AuthGate to route away)
    // animates forever, so pumpAndSettle would never return.
    await tester.pump();
    await tester.pump();

    verify(() => mockAuth.updatePassword('secret123')).called(1);
    verify(() => mockAuth.completePasswordSetup()).called(1);
  });

  testWidgets('does not clear the flag in recovery mode', (tester) async {
    when(() => mockAuth.updatePassword(any())).thenAnswer((_) async {});

    await pumpScreen(tester, clearFlag: false);

    await tester.enterText(find.widgetWithText(TextFormField, 'New password'), 'secret123');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), 'secret123');
    await tester.tap(find.text('Save password'));
    await tester.pump();
    await tester.pump();

    verify(() => mockAuth.updatePassword('secret123')).called(1);
    verifyNever(() => mockAuth.completePasswordSetup());
  });

  testWidgets('shows an error message when the update fails', (tester) async {
    when(() => mockAuth.updatePassword(any())).thenThrow(Exception('weak password'));

    await pumpScreen(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'New password'), 'secret123');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), 'secret123');
    await tester.tap(find.text('Save password'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not set password'), findsOneWidget);
  });
}
