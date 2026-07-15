import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/auth/auth_service.dart';
import 'package:test_flutter/shared/widgets/logout_button.dart';

class MockAuthService extends Mock implements AuthService {}

void main() {
  testWidgets('tapping the logout button calls signOut', (tester) async {
    final mockAuth = MockAuthService();
    when(() => mockAuth.signOut()).thenAnswer((_) async {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(mockAuth)],
        child: const MaterialApp(home: Scaffold(body: LogoutButton())),
      ),
    );

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pump();

    verify(() => mockAuth.signOut()).called(1);
  });
}
