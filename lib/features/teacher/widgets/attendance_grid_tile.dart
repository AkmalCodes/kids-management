import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/child.dart';
import '../../../core/controllers/child_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/attendance_status_chip.dart';
import '../../../shared/widgets/app_loader.dart';
import 'grid_person_tile.dart';

// One child in the attendance grid: avatar, name, a status badge and a
// caption line. Purely presentational -- it takes the record it should render
// and callbacks, and performs no writes.
//
// Screen design AA1 ("arrival board"): a child with no record yet is
// WAITING -- faded avatar, no badge, a pink "Check in" caption -- so the ones
// still to arrive stand out; a marked child gets a corner badge in its
// status colour and its arrival time (or "Absent"/"Excused") underneath. That keeps the marking logic in one
// place (MarkAttendanceScreen) and makes this widget testable on its own.
class AttendanceGridTile extends ConsumerWidget {
  const AttendanceGridTile({
    super.key,
    required this.child,
    required this.attendance,
    required this.onTap,
    this.onLongPress,
  });

  final Child child;

  // Null means no record exists for today, which is a real and important
  // state: it is how a teacher sees who is still outstanding.
  final Attendance? attendance;

  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final record = attendance;
    return GridPersonTile(
      name: child.name,
      onTap: onTap,
      onLongPress: onLongPress,
      badge: record == null ? null : AttendanceStatusBadge(status: record.status),
      caption: _caption(record),
      // The child avatar: a rounded square with a translucent border, the
      // photo clipped inside. Deliberately NOT a CircleAvatar (that bug is
      // what the border+ClipRRect here fixed) -- the circular variant is the
      // teacher tile's job.
      avatar: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colors.primary.withValues(alpha: 0.25),
            width: 2,
          ),
        ),
        child: ClipRRect(
          // 14 not 16: sits inside the 2px border so the photo does not bleed
          // over the rounded corner.
          borderRadius: BorderRadius.circular(14),
          // Waiting children are faded so the arrived ones read as "done".
          child: Opacity(
            key: const Key('tile-avatar-opacity'),
            opacity: record == null ? 0.5 : 1,
            child: _photo(colors, ref),
          ),
        ),
      ),
    );
  }

  // The child's photo, filling the whole rounded square.
  //
  // Deliberately not SignedAvatar: that widget is CircleAvatar-based by
  // contract ("a round avatar"), so inside a square frame it renders a circle
  // with the corners left empty -- which is exactly the bug this replaced.
  // Other call sites still want the round one, so it is left alone.
  Widget _photo(ColorScheme colors, WidgetRef ref) {
    final path = child.avatarPath;
    if (path == null) return _placeholder(colors);

    return ref.watch(signedChildAvatarUrlProvider(path)).when(
          loading: () => ColoredBox(
            color: colors.surfaceContainerHighest,
            child: const Center(child: AppLoader(size: 16)),
          ),
          error: (_, _) => _placeholder(colors, icon: Icons.broken_image_outlined),
          // cover: fill the frame, cropping overflow, rather than letter-boxing
          // a portrait photo inside a square.
          data: (url) => Image.network(url, fit: BoxFit.cover),
        );
  }

  Widget _placeholder(ColorScheme colors, {IconData icon = Icons.person_outline}) {
    return ColoredBox(
      color: colors.primaryContainer,
      child: Icon(icon, size: 32, color: colors.onPrimaryContainer),
    );
  }

  Widget _caption(Attendance? record) {
    if (record == null) {
      // FittedBox: on a narrow tile (or with large accessibility text) the
      // label shrinks rather than overflowing the tile.
      return const FittedBox(
        key: Key('status-waiting'),
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_camera_outlined, size: 11, color: AppTheme.accentPink),
            SizedBox(width: 3),
            Text('Check in',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.accentPink)),
          ],
        ),
      );
    }
    final text = switch (record.status) {
      AttendanceStatus.present || AttendanceStatus.late => formatClock(record.createdAt),
      _ => AttendanceStatusStyle.of(record.status).label,
    };
    return Text(text,
        maxLines: 1,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.mutedText));
  }
}
