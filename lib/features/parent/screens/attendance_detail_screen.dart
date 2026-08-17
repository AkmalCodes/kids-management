import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/attendance.dart';
import '../../../shared/util/date_display.dart';
import '../../../shared/widgets/attendance_status_chip.dart';
import '../../../shared/widgets/signed_photo_thumbnail.dart';
import '../../../shared/widgets/app_loader.dart';

// Opened by tapping an attendance card in the parent view. Shows the day's
// status plus the check-in and belongings photos at a large size.
class AttendanceDetailScreen extends StatelessWidget {
  const AttendanceDetailScreen({super.key, required this.record, required this.childName});

  final Attendance record;
  final String childName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$childName — ${isoWithWeekday(record.date)}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Text('Status', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              AttendanceStatusChip(status: record.status),
            ],
          ),
          if (record.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(record.notes),
          ],
          const SizedBox(height: 24),
          Text('Check-in photo', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _LargePhoto(path: record.photoPath),
          const SizedBox(height: 24),
          Text('Belongings photo', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _LargePhoto(path: record.belongingsPhotoPath),
        ],
      ),
    );
  }
}

// A large signed-URL photo, or a muted "none" placeholder when absent.
class _LargePhoto extends ConsumerWidget {
  const _LargePhoto({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (path == null) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text('None', style: TextStyle(color: Theme.of(context).disabledColor)),
      );
    }
    final urlAsync = ref.watch(signedPhotoUrlProvider(path!));
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: urlAsync.when(
          loading: () => const ColoredBox(
            color: Color(0x11000000),
            child: Center(child: AppLoader()),
          ),
          error: (_, _) => const ColoredBox(
            color: Color(0x11000000),
            child: Icon(Icons.broken_image_outlined, size: 40),
          ),
          data: (url) => Image.network(url, fit: BoxFit.cover),
        ),
      ),
    );
  }
}
