import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/services/schedule_service.dart';
import '../../../shared/widgets/weekly_schedule_grid.dart';

class TeacherScheduleScreen extends ConsumerWidget {
  const TeacherScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    return userAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (user) {
        if (user == null) return const SizedBox.shrink();
        final scheduleAsync =
            ref.watch(scheduleProvider((type: 'teacher', refId: user.id)));
        return scheduleAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (schedule) => SingleChildScrollView(
            child: WeeklyScheduleGrid(entries: schedule?.entries ?? []),
          ),
        );
      },
    );
  }
}
