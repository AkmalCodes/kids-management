import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_controller.dart';
import '../auth/role_router.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/set_password_screen.dart';
import '../../shared/widgets/app_loader.dart';

// The single entry point main.dart points at. Its only job is the
// logged-out/logged-in split; once a user exists, RoleRouter takes over
// deciding *which* shell to show based on their role.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    // Defaults to false while the stream hasn't emitted yet, so it never
    // blocks the normal startup path.
    final recovering = ref.watch(passwordRecoveryProvider).value ?? false;

    return userAsync.when(
      loading: () => const Scaffold(
        body: Center(child: AppLoader()),
      ),
      // On error, fall back to LoginScreen rather than an error page —
      // most likely cause is "no session yet", which isn't really an error
      // from the user's perspective.
      error: (_, _) => const LoginScreen(),
      data: (user) {
        // Recovery takes precedence over everything: the user followed a
        // "forgot password" link (they're authenticated via a recovery
        // session) and must set a new password before doing anything else.
        // clearMustSetPasswordFlag: false since this isn't the invite path.
        if (recovering) return const SetPasswordScreen(clearMustSetPasswordFlag: false);
        if (user == null) return const LoginScreen();
        // Freshly-invited accounts arrive here with a valid session (from
        // the invite deep link) but no password yet -- force that first.
        if (user.mustSetPassword) return const SetPasswordScreen();
        return const RoleRouter();
      },
    );
  }
}
