import 'package:flutter/material.dart';
import '../../../core/models/app_user.dart';
import '../../../core/controllers/profile_controller.dart';
import '../../../shared/widgets/signed_avatar.dart';
import 'grid_person_tile.dart';

// Where the signed-in teacher is in their working day, for the Teachers-grid
// badge. Derived from today's staff_attendance row, not a DB concept, so it
// lives here. Co-teacher tiles pass null (their clock rows aren't readable).
enum StaffClockState { notClockedIn, working, done }

// One teacher in the Teachers grid: a circular avatar + one-line name, and --
// for the signed-in teacher only -- a clock-state badge. Circular on purpose:
// the child tile is a rounded square, teachers read as people not classes.
class StaffGridTile extends StatelessWidget {
  const StaffGridTile({
    super.key,
    required this.teacher,
    required this.onTap,
    this.clockState,
  });

  final AppUser teacher;
  final StaffClockState? clockState;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GridPersonTile(
      name: teacher.name,
      onTap: onTap,
      badge: clockState == null ? null : _badge(Theme.of(context).colorScheme),
      avatar: SignedAvatar(
        urlProvider: teacher.avatarPath == null
            ? null
            : signedAvatarUrlProvider(teacher.avatarPath!),
      ),
    );
  }

  Widget _badge(ColorScheme colors) {
    final (icon, color) = switch (clockState!) {
      StaffClockState.notClockedIn => (Icons.schedule, Colors.amber.shade700),
      StaffClockState.working => (Icons.access_time_filled, Colors.green.shade600),
      StaffClockState.done => (Icons.logout, colors.onSurfaceVariant),
    };
    return Container(
      decoration: BoxDecoration(color: colors.surface, shape: BoxShape.circle),
      padding: const EdgeInsets.all(1),
      child: Icon(icon, size: 20, color: color),
    );
  }
}
