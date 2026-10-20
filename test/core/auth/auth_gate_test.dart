import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawankecil/core/auth/auth_gate.dart';
import 'package:kawankecil/core/auth/auth_controller.dart';
import 'package:kawankecil/core/models/app_user.dart';
import 'package:kawankecil/features/auth/login_screen.dart';
import 'package:kawankecil/features/auth/set_password_screen.dart';

AppUser _user({bool mustSetPassword = false}) => AppUser(
  id: 'uid-1',
  role: 'teacher',
  name: 'Test',
  phone: '',
  centerId: 'center-1',
  mustSetPassword: mustSetPassword,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

void main() {
  testWidgets('shows LoginScreen when there is no user', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(null)),
        passwordRecoveryProvider.overrideWith((ref) => Stream.value(false)),
      ],
      child: const MaterialApp(home: AuthGate()),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('shows SetPasswordScreen when the user must set a password', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_user(mustSetPassword: true))),
        passwordRecoveryProvider.overrideWith((ref) => Stream.value(false)),
      ],
      child: const MaterialApp(home: AuthGate()),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SetPasswordScreen), findsOneWidget);
  });

  testWidgets('shows SetPasswordScreen (recovery mode) when a recovery link fires',
      (tester) async {
    // A normal, fully-provisioned user -- but a recovery deep link has
    // fired, so they must still set a new password first.
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_user())),
        passwordRecoveryProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: const MaterialApp(home: AuthGate()),
    ));
    await tester.pumpAndSettle();

    final screen = tester.widget<SetPasswordScreen>(find.byType(SetPasswordScreen));
    expect(screen.clearMustSetPasswordFlag, isFalse);
  });
}
