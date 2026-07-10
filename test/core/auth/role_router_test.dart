import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_flutter/core/auth/auth_service.dart';
import 'package:test_flutter/core/auth/role_router.dart';
import 'package:test_flutter/core/models/app_user.dart';

AppUser _user(String role) => AppUser(
  id: 'uid-1',
  role: role,
  name: 'Test',
  phone: '',
  centerId: 'c-1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'd-1',
  updatedBy: 'd-1',
);

void main() {
  testWidgets('routes parent to ParentShell', (tester) async {
    await tester.pumpWidget(ProviderScope(
      // overrideWith replaces the real provider (which would hit Supabase)
      // with a fake stream — this is how we test routing logic in
      // isolation, without a real network connection.
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_user('parent'))),
      ],
      child: const MaterialApp(home: RoleRouter()),
    ));
    await tester.pump();
    // Shells now render tab content ("Schedule — coming soon") instead of
    // the plain-text placeholder from before Task 7.
    expect(find.text('Schedule — coming soon'), findsOneWidget);
  });

  testWidgets('routes teacher to TeacherShell', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_user('teacher'))),
      ],
      child: const MaterialApp(home: RoleRouter()),
    ));
    await tester.pump();
    expect(find.text('Schedule — coming soon'), findsOneWidget);
  });

  testWidgets('routes director to DirectorShell', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_user('director'))),
      ],
      child: const MaterialApp(home: RoleRouter()),
    ));
    await tester.pump();
    expect(find.text('Teachers — coming soon'), findsOneWidget);
  });
}
