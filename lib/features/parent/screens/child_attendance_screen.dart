import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/child.dart';
import '../../../core/services/attendance_service.dart';
import '../../../core/services/child_service.dart';
import '../../../shared/widgets/attendance_status_chip.dart';

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
          future: ref.read(childServiceProvider).fetchForParent(user.id),
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
          child: Text(child.name, style: Theme.of(context).textTheme.titleLarge),
        ),
        FutureBuilder<List<Attendance>>(
          future: ref.read(attendanceServiceProvider).fetchForChild(child.id),
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
                  ListTile(
                    title: Text(record.date),
                    trailing: AttendanceStatusChip(status: record.status),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
