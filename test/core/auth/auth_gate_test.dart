import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_flutter/core/auth/auth_gate.dart';
import 'package:test_flutter/core/auth/auth_service.dart';
import 'package:test_flutter/core/models/app_user.dart';
import 'package:test_flutter/features/auth/login_screen.dart';
import 'package:test_flutter/features/auth/set_password_screen.dart';

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
      ],
      child: const MaterialApp(home: AuthGate()),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SetPasswordScreen), findsOneWidget);
  });
}
