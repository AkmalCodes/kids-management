import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawankecil/features/auth/forgot_password_screen.dart';
import 'package:kawankecil/features/auth/login_screen.dart';
import 'package:kawankecil/shared/widgets/app_logo.dart';

void main() {
  testWidgets('LoginScreen shows two fields and a Sign In button', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('LoginScreen shows the app logo instead of the generic icon', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );
    expect(find.byType(AppLogo), findsOneWidget);
    expect(find.byIcon(Icons.child_care), findsNothing);
  });

  testWidgets('tapping Forgot password? opens the ForgotPasswordScreen', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );

    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
  });

  testWidgets('shows email error when Sign In tapped with empty fields', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );
    await tester.tap(find.text('Sign In'));
    await tester.pump();
    expect(find.text('Please enter your email'), findsOneWidget);
  });

  testWidgets('shows password error when only email filled', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );
    await tester.enterText(find.byType(TextFormField).first, 'test@test.com');
    await tester.tap(find.text('Sign In'));
    await tester.pump();
    expect(find.text('Please enter your password'), findsOneWidget);
  });

  testWidgets('email placeholder fades out on focus instead of floating up',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );

    final emailOpacity = find.byKey(const Key('email-hint-opacity'));

    expect(tester.widget<AnimatedOpacity>(emailOpacity).opacity, 1.0);

    await tester.tap(find.byType(TextFormField).first);
    await tester.pump();

    expect(tester.widget<AnimatedOpacity>(emailOpacity).opacity, 0.0);
  });
}
