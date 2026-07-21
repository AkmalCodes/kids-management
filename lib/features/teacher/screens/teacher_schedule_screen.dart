import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/services/schedule_service.dart';
import '../../../shared/widgets/schedule_agenda_view.dart';

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
        final entriesAsync =
            ref.watch(scheduleEntriesProvider((type: 'teacher', refId: user.id)));
        return entriesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (entries) => ScheduleAgendaView(
            entries: entries,
            type: 'teacher',
            refId: user.id,
            centerId: user.centerId,
            editable: true,
          ),
        );
      },
    );
  }
}
