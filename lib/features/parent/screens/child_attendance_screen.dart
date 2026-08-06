import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/child.dart';
import '../../../core/controllers/attendance_controller.dart';
import '../../../core/controllers/child_controller.dart';
import '../../../shared/util/date_display.dart';
import '../../../shared/widgets/attendance_status_chip.dart';
import '../../../shared/widgets/signed_avatar.dart';
import '../../../shared/widgets/signed_photo_thumbnail.dart';
import 'attendance_detail_screen.dart';

class ChildAttendanceScreen extends ConsumerWidget {
  const ChildAttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    return userAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (user) {
        if (user == null) return const SizedBox.shrink();
        return FutureBuilder<List<Child>>(
          future: ref.read(childControllerProvider).fetchForParent(user.id),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final children = snapshot.data!;
            if (children.isEmpty) {
              return const Center(child: Text('No children linked to your account yet.'));
            }
            return ListView(
              children: [
                for (final child in children) _ChildAttendanceSection(child: child),
              ],
            );
          },
        );
      },
    );
  }
}

class _ChildAttendanceSection extends ConsumerWidget {
  const _ChildAttendanceSection({required this.child});

  final Child child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              SignedAvatar(
                urlProvider: child.avatarPath == null
                    ? null
                    : signedChildAvatarUrlProvider(child.avatarPath!),
                radius: 18,
              ),
              const SizedBox(width: 10),
              Text(child.name, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
        FutureBuilder<List<Attendance>>(
          future: ref.read(attendanceControllerProvider).fetchForChild(child.id),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final records = snapshot.data!;
            if (records.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No attendance records yet.'),
              );
            }
            return Column(
              children: [
                for (final record in records)
                  _AttendanceCard(record: record, childName: child.name),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  const _AttendanceCard({required this.record, required this.childName});

  final Attendance record;
  final String childName;

  @override
  Widget build(BuildContext context) {
    final hasPhotos = record.photoPath != null || record.belongingsPhotoPath != null;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _photoThumbnails(),
        title: Text(isoWithWeekday(record.date)),
        subtitle: hasPhotos ? const Text('Tap to view photos') : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AttendanceStatusChip(status: record.status),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AttendanceDetailScreen(record: record, childName: childName),
          ),
        ),
      ),
    );
  }

  // Either or both may be absent since both photos are optional -- shows a
  // person placeholder if neither exists.
  Widget _photoThumbnails() {
    final thumbnails = [
      if (record.photoPath != null)
        SignedPhotoThumbnail(photoPath: record.photoPath!, radius: 16),
      if (record.belongingsPhotoPath != null)
        SignedPhotoThumbnail(photoPath: record.belongingsPhotoPath!, radius: 16),
    ];
    if (thumbnails.isEmpty) {
      return const CircleAvatar(radius: 16, child: Icon(Icons.event_note_outlined, size: 18));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final thumbnail in thumbnails)
          Padding(padding: const EdgeInsets.only(right: 4), child: thumbnail),
      ],
    );
  }
}
