import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_controller.dart';

// AuthGate watches currentUserProvider and swaps back to LoginScreen
// automatically once the session clears, so this button needs no
// navigation logic of its own — just call signOut() and let it react.
class LogoutButton extends ConsumerWidget {
  const LogoutButton({super.key});

  Future<void> _confirmAndSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to sign in again to continue.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(authControllerProvider).signOut();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.logout),
      tooltip: 'Sign out',
      onPressed: () => _confirmAndSignOut(context, ref),
    );
  }
}
