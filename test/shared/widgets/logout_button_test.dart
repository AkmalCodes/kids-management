import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kawankecil/core/auth/auth_controller.dart';
import 'package:kawankecil/shared/widgets/logout_button.dart';

class MockAuthController extends Mock implements AuthController {}

void main() {
  late MockAuthController mockAuth;

  setUp(() {
    mockAuth = MockAuthController();
    when(() => mockAuth.signOut()).thenAnswer((_) async {});
  });

  Future<void> pumpButton(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          overrides: [authControllerProvider.overrideWithValue(mockAuth)],
          child: const MaterialApp(home: Scaffold(body: LogoutButton())),
        ),
      );

  testWidgets('tapping the icon shows a confirmation dialog, not an immediate sign-out',
      (tester) async {
    await pumpButton(tester);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    expect(find.text('Sign out?'), findsOneWidget);
    verifyNever(() => mockAuth.signOut());
  });

  testWidgets('confirming signs the user out', (tester) async {
    await pumpButton(tester);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign Out'));
    await tester.pumpAndSettle();

    verify(() => mockAuth.signOut()).called(1);
  });

  testWidgets('cancelling does not sign the user out', (tester) async {
    await pumpButton(tester);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => mockAuth.signOut());
    expect(find.text('Sign out?'), findsNothing);
  });
}
