import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_service.dart';

// AuthGate watches currentUserProvider and swaps back to LoginScreen
// automatically once the session clears, so this button needs no
// navigation logic of its own — just call signOut() and let it react.
class LogoutButton extends ConsumerWidget {
  const LogoutButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.logout),
      tooltip: 'Sign out',
      onPressed: () => ref.read(authServiceProvider).signOut(),
    );
  }
}
