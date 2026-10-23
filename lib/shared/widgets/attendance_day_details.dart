import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/controllers/child_controller.dart';
import '../../core/models/attendance.dart';
import '../../core/models/child.dart';
import '../../core/theme/app_theme.dart';
import 'attendance_photos.dart';
import 'attendance_status_chip.dart';
import 'signed_avatar.dart';

// One child's attendance for one day, read-only: status + arrival time,
// the check-in and belongings photos large, and the teacher's note. Shared
// by the director's child sheet (AA4) and the parent's day screen (AA6), so
// both see exactly what the teacher recorded.
class AttendanceDayDetails extends StatelessWidget {
  const AttendanceDayDetails({super.key, required this.record});

  final Attendance record;

  @override
  Widget build(BuildContext context) {
    final style = AttendanceStatusStyle.of(record.status);
    final arrived = record.status == AttendanceStatus.present || record.status == AttendanceStatus.late;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: AttendanceStatusChip(
            status: record.status,
            label: arrived ? '${style.label} · checked in ${formatClock(record.createdAt)}' : null,
          ),
        ),
        const SizedBox(height: 14),
        const _Label('CHECK-IN PHOTO'),
        const SizedBox(height: 8),
        _PhotoBox(path: record.photoPath, aspectRatio: 16 / 10, empty: 'No check-in photo'),
        const SizedBox(height: 14),
        const _Label('BELONGINGS'),
        const SizedBox(height: 8),
        _PhotoBox(path: record.belongingsPhotoPath, aspectRatio: 16 / 8, empty: 'No belongings photo'),
        if (record.notes.trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          const _Label('NOTE FROM TEACHER'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppTheme.barTint, borderRadius: BorderRadius.circular(16)),
            child: Text(record.notes.trim(),
                style: const TextStyle(fontSize: 14, height: 1.4, color: AppTheme.bodyText)),
          ),
        ],
      ],
    );
  }
}

// Read-only sheet: a child's day for the director (who can see, not mark).
Future<void> showAttendanceDaySheet(
  BuildContext context, {
  required Child child,
  required Attendance? record,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _DaySheet(child: child, record: record),
  );
}

class _DaySheet extends ConsumerWidget {
  const _DaySheet({required this.child, required this.record});
  final Child child;
  final Attendance? record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = record;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        // Never taller than ~90% of the screen; the content scrolls.
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: AppTheme.fieldBorder, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  SignedAvatar(
                    urlProvider:
                        child.avatarPath == null ? null : signedChildAvatarUrlProvider(child.avatarPath!),
                    radius: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(child.name,
                            style: const TextStyle(
                                fontSize: 19, fontWeight: FontWeight.w800, color: AppTheme.onAccent)),
                        if (child.className.isNotEmpty)
                          Text(child.className, style: const TextStyle(fontSize: 12, color: AppTheme.mutedText)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    color: AppTheme.mutedText,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (r == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('Not checked in yet.',
                      textAlign: TextAlign.center, style: TextStyle(color: AppTheme.mutedText)),
                )
              else
                AttendanceDayDetails(record: r),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.9, color: AppTheme.mutedText));
}

class _PhotoBox extends StatelessWidget {
  const _PhotoBox({required this.path, required this.aspectRatio, required this.empty});
  final String? path;
  final double aspectRatio;
  final String empty;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: path == null
            ? ColoredBox(
                color: AppTheme.barTint,
                child: Center(child: Text(empty, style: const TextStyle(color: AppTheme.mutedText))),
              )
            : SignedAttendancePhoto(path!),
      ),
    );
  }
}
