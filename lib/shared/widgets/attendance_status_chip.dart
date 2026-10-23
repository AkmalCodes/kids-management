import 'package:flutter/material.dart';
import '../../core/models/attendance.dart';

// One look per attendance status, shared by every role's screens so
// "present" always reads the same way (screen design AA, Figma "Screen
// designs"). Same tone family as LessonPlanStatusChip: a pale background, a
// strong foreground, a dot.
class AttendanceStatusStyle {
  const AttendanceStatusStyle(this.background, this.foreground, this.label, this.icon);

  final Color background;
  final Color foreground;
  final String label;
  final IconData icon; // for corner badges on avatar tiles

  static AttendanceStatusStyle of(AttendanceStatus status) => switch (status) {
        AttendanceStatus.present =>
          const AttendanceStatusStyle(Color(0xFFE3F4EA), Color(0xFF2E7D4F), 'Present', Icons.check),
        AttendanceStatus.late =>
          const AttendanceStatusStyle(Color(0xFFFFF1D6), Color(0xFFB7791F), 'Late', Icons.schedule),
        AttendanceStatus.absent =>
          const AttendanceStatusStyle(Color(0xFFFDE7E4), Color(0xFFB3261E), 'Absent', Icons.close),
        AttendanceStatus.excused =>
          const AttendanceStatusStyle(Color(0xFFE6EEF8), Color(0xFF2F5E8E), 'Excused', Icons.remove),
      };
}

// "07:52" in the device's local time. Attendance/clock timestamps are stored
// in UTC (TIMESTAMPTZ), so every display goes through here.
String formatClock(DateTime t) {
  final local = t.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

// Small dot pill: "● Present". [label] overrides the text, e.g.
// "Present · 07:52".
class AttendanceStatusChip extends StatelessWidget {
  const AttendanceStatusChip({super.key, required this.status, this.label});

  final AttendanceStatus status;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final style = AttendanceStatusStyle.of(status);
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 4, 10, 4),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: style.foreground, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label ?? style.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: style.foreground, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// The round corner badge on an avatar tile: white ring, status colour, icon.
class AttendanceStatusBadge extends StatelessWidget {
  const AttendanceStatusBadge({super.key, required this.status, this.size = 20});

  final AttendanceStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = AttendanceStatusStyle.of(status);
    return Container(
      key: Key('status-badge-${status.name}'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: style.foreground,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Icon(style.icon, size: size * 0.6, color: Colors.white),
    );
  }
}
