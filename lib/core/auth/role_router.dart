import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_service.dart';
import '../../features/parent/parent_shell.dart';
import '../../features/teacher/teacher_shell.dart';
import '../../features/director/director_shell.dart';

// ConsumerWidget (not ConsumerStatefulWidget): this widget has no local
// state of its own to track — it only ever re-renders in response to
// currentUserProvider changing, so a plain build(context, ref) is enough.
class RoleRouter extends ConsumerWidget {
  const RoleRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    // AsyncValue.when forces handling all three states a stream-backed
    // provider can be in — loading (waiting on Supabase), error (e.g.
    // network failure), and data (an AppUser? — which itself can be null
    // if the user is logged out). Skipping a branch is a compile error,
    // so we can't accidentally forget to handle the loading/error UI.
    return userAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(child: Text('Error loading profile: $e')),
      ),
      data: (user) {
        if (user == null) {
          return const Scaffold(
            body: Center(
              child: Text('Account not found. Contact your administrator.'),
            ),
          );
        }
        // Switch expression on role string: this is the single point in
        // the app that maps a Postgres `profiles.role` value to a screen.
        return switch (user.role) {
          'parent'   => const ParentShell(),
          'teacher'  => const TeacherShell(),
          'director' => const DirectorShell(),
          final role => Scaffold(
              body: Center(child: Text('Unknown role: $role')),
            ),
        };
      },
    );
  }
}
