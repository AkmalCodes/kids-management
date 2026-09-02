import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/app_user.dart';
import '../../core/controllers/photo_capture_controller.dart';
import '../../core/controllers/profile_controller.dart';
import '../../shared/widgets/avatar_source_sheet.dart';
import '../../shared/widgets/signed_avatar.dart';
import 'change_password_screen.dart';
import 'person_detail_screen.dart';
import 'widgets/staff_attendance_toggle.dart';
import '../../shared/widgets/app_loader.dart';

// Shared account-settings tab for every role. Shows the user's avatar,
// name, email and role, plus actions to change the avatar and password.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _changeAvatar(BuildContext context, WidgetRef ref, AppUser user) async {
    final source = await showAvatarSourceSheet(context);
    if (source == null) return;
    final capture = ref.read(photoCaptureControllerProvider);
    final photo = source == AvatarSource.gallery
        ? await capture.pickFromGallery()
        : await capture.captureFromCamera();
    if (photo == null) return;
    final profile = ref.read(profileControllerProvider);
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
      loading: () => const Center(child: AppLoader()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (user) {
        if (user == null) return const SizedBox.shrink();
        final email = ref.read(authControllerProvider).currentEmail ?? '';
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Column(
                children: [
                  SignedAvatar(
                    urlProvider: user.avatarPath == null
                        ? null
                        : signedAvatarUrlProvider(user.avatarPath!),
                    radius: 48,
                  ),
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
            const StaffAttendanceToggle(),
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
              onPressed: () => ref.read(authControllerProvider).signOut(),
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
