import 'package:flutter/material.dart';
import '../../../shared/util/name_display.dart';

// The shared attendance-grid tile shell: a size-stable square avatar slot
// with an optional inset corner badge, and a fixed one-line name beneath.
// Presentational only -- it knows nothing about Child / AppUser / circles /
// squares. Callers pass a finished `avatar` widget and a finished `badge`.
// AttendanceGridTile (children, rounded-square photo + status badge) and
// StaffGridTile (teachers, circular avatar + clock badge) both wrap this so
// the Piece-A "name length never changes the avatar size" behaviour stays
// identical for both.
class GridPersonTile extends StatelessWidget {
  const GridPersonTile({
    super.key,
    required this.avatar,
    required this.name,
    required this.onTap,
    this.badge,
    this.onLongPress,
  });

  final Widget avatar;
  final String name;
  final Widget? badge;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final label = shortLabelName(name);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          // The name below is a fixed single line, so the avatar absorbs
          // whatever height is left and stays the same size on every tile. A
          // fixed square here overflowed by ~1px at normal text size, and far
          // worse under accessibility text scaling.
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    avatar,
                    if (badge != null)
                      Positioned(right: 6, bottom: 6, child: badge!),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label.isEmpty ? ' ' : label,
            maxLines: 1,
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
}
