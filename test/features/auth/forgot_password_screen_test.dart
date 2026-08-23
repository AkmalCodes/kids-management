import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kids_management/core/auth/auth_controller.dart';
import 'package:kids_management/features/auth/forgot_password_screen.dart';

class MockAuthController extends Mock implements AuthController {}

void main() {
  late MockAuthController mockAuth;

  setUp(() {
    mockAuth = MockAuthController();
  });

  Future<void> pumpScreen(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          overrides: [authControllerProvider.overrideWithValue(mockAuth)],
          child: const MaterialApp(home: ForgotPasswordScreen()),
        ),
      );

  testWidgets('blocks send when email is empty', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter your email'), findsOneWidget);
    verifyNever(() => mockAuth.sendPasswordReset(any()));
  });

  testWidgets('blocks send when email has no @', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'not-an-email');
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email'), findsOneWidget);
    verifyNever(() => mockAuth.sendPasswordReset(any()));
  });

  testWidgets('sends the reset email and shows the confirmation', (tester) async {
    when(() => mockAuth.sendPasswordReset(any())).thenAnswer((_) async {});

    await pumpScreen(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'jane@example.com');
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();

    verify(() => mockAuth.sendPasswordReset('jane@example.com')).called(1);
    expect(find.textContaining("we've sent a link"), findsOneWidget);
  });

  testWidgets('shows an error message when sending fails', (tester) async {
    when(() => mockAuth.sendPasswordReset(any())).thenThrow(Exception('rate limit'));

    await pumpScreen(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'jane@example.com');
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not send reset email'), findsOneWidget);
  });
}
