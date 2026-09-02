import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/child.dart';
import '../../../core/controllers/child_controller.dart';
import '../../../shared/widgets/app_loader.dart';

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
        children: [
          // Expanded rather than a fixed AspectRatio: the name takes its
          // natural height first and the photo absorbs whatever is left. A
          // fixed square overflowed by ~1px at normal text size, and would
          // have overflowed much harder under accessibility text scaling.
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    // Translucent so it reads as part of the palette rather
                    // than a hard outline around every child.
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.25),
                      width: 2,
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        // 14 not 16: sits inside the 2px border so the photo
                        // does not bleed over the rounded corner.
                        borderRadius: BorderRadius.circular(14),
                        child: _photo(colors, ref),
                      ),
                      // Inset rather than flush to the corner, so the badge
                      // floats over the photo instead of colliding with the
                      // rounded edge.
                      Positioned(right: 6, bottom: 6, child: _badge(colors)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            child.name,
            // Two lines because real names are long -- one line ellipsized
            // most of them away.
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
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
