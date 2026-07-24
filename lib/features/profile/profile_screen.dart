import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_service.dart';
import '../../core/models/app_user.dart';
import '../../core/services/photo_capture_service.dart';
import '../../core/services/profile_service.dart';
import 'change_password_screen.dart';
import 'person_detail_screen.dart';

// Shared account-settings tab for every role. Shows the user's avatar,
// name, email and role, plus actions to change the avatar and password.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _changeAvatar(BuildContext context, WidgetRef ref, AppUser user) async {
    final action = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.of(sheetContext).pop(false),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(sheetContext).pop(true),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;
    final capture = ref.read(photoCaptureServiceProvider);
    final photo = action ? await capture.pickFromGallery() : await capture.captureFromCamera();
    if (photo == null) return;
    final profile = ref.read(profileServiceProvider);
    try {
      final path = await profile.uploadAvatar(userId: user.id, photo: photo);
      await profile.setAvatarPath(path);
      ref.invalidate(currentUserProvider);
      // Drop any cached signed URL for this path so the new image is fetched.
      ref.invalidate(signedAvatarUrlProvider(path));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update photo: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    return userAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (user) {
        if (user == null) return const SizedBox.shrink();
        final email = ref.read(authServiceProvider).currentEmail ?? '';
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Column(
                children: [
                  _Avatar(avatarPath: user.avatarPath),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => _changeAvatar(context, ref, user),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Change photo'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _InfoTile(icon: Icons.person_outline, label: 'Name', value: user.name),
            _InfoTile(icon: Icons.email_outlined, label: 'Email', value: email),
            _InfoTile(
              icon: Icons.badge_outlined,
              label: 'Role',
              value: user.role[0].toUpperCase() + user.role.substring(1),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => PersonDetailScreen(person: user)),
              ),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Profile details'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
              ),
              icon: const Icon(Icons.lock_outline),
              label: const Text('Change password'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => ref.read(authServiceProvider).signOut(),
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Avatar extends ConsumerWidget {
  const _Avatar({required this.avatarPath});

  final String? avatarPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const radius = 48.0;
    if (avatarPath == null) {
      return const CircleAvatar(radius: radius, child: Icon(Icons.person_outline, size: 48));
    }
    final urlAsync = ref.watch(signedAvatarUrlProvider(avatarPath!));
    return urlAsync.when(
      loading: () => const CircleAvatar(
        radius: radius,
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, _) =>
          const CircleAvatar(radius: radius, child: Icon(Icons.broken_image_outlined, size: 40)),
      data: (url) => CircleAvatar(radius: radius, backgroundImage: NetworkImage(url)),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label, style: Theme.of(context).textTheme.bodySmall),
      subtitle: Text(value, style: Theme.of(context).textTheme.bodyLarge),
    );
  }
}
