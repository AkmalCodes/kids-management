import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/child.dart';
import '../../../core/controllers/child_controller.dart';
import '../../../shared/widgets/signed_avatar.dart';

// One child in the attendance grid: avatar, name, and a badge showing today's
// status. Purely presentational -- it takes the record it should render and
// two callbacks, and performs no writes. That keeps the marking logic in one
// place (MarkAttendanceScreen) and makes this widget testable on its own.
class AttendanceGridTile extends ConsumerWidget {
  const AttendanceGridTile({
    super.key,
    required this.child,
    required this.attendance,
    required this.onTap,
    required this.onLongPress,
  });

  final Child child;

  // Null means no record exists for today, which is a real and important
  // state: it is how a teacher sees who is still outstanding.
  final Attendance? attendance;

  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                // Translucent so it reads as part of the palette rather than
                // a hard outline around every child.
                border: Border.all(color: colors.primary.withValues(alpha: 0.25), width: 2),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Center(
                        child: SignedAvatar(
                          urlProvider: child.avatarPath == null
                              ? null
                              : signedChildAvatarUrlProvider(child.avatarPath!),
                          radius: 34,
                        ),
                      ),
                    ),
                  ),
                  // Inset rather than flush to the corner, so the badge floats
                  // over the avatar instead of colliding with its rounded edge.
                  Positioned(right: 6, bottom: 6, child: _badge(colors)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            child.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

  // present/absent are the only statuses this UI can set. Anything else --
  // including late and excused, which exist in the enum but have never been
  // offered -- renders as unmarked rather than inventing an icon for a state
  // a teacher cannot produce.
  Widget _badge(ColorScheme colors) {
    final (key, icon, color) = switch (attendance?.status) {
      AttendanceStatus.present =>
        (const Key('status-badge-present'), Icons.check_circle, Colors.green.shade600),
      AttendanceStatus.absent =>
        (const Key('status-badge-absent'), Icons.cancel, Colors.red.shade600),
      _ => (
          const Key('status-badge-unmarked'),
          Icons.help,
          Colors.amber.shade700,
        ),
    };

    return Container(
      key: key,
      decoration: BoxDecoration(color: colors.surface, shape: BoxShape.circle),
      padding: const EdgeInsets.all(1),
      child: Icon(icon, size: 20, color: color),
    );
  }
}
