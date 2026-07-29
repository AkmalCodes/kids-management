import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/models/class_group.dart';
import '../../../core/services/class_service.dart';
import '../../../core/services/schedule_service.dart';
import '../../../shared/widgets/schedule_agenda_view.dart';

// A teacher's schedule is their class's schedule (§6.8). Resolves the class
// they're assigned to, then shows/edits that class's entries. (Multiple
// classes per teacher isn't a real case yet; shows the first for now.)
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
        return FutureBuilder<List<ClassGroup>>(
          future: ref.read(classServiceProvider).fetchForTeacher(user.id),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final classes = snapshot.data!;
            if (classes.isEmpty) {
              return const Center(child: Text("You're not assigned to a class yet."));
            }
            final classGroup = classes.first;
            final entriesAsync =
                ref.watch(scheduleEntriesProvider((type: 'class', refId: classGroup.id)));
            return entriesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (entries) => ScheduleAgendaView(
                entries: entries,
                type: 'class',
                refId: classGroup.id,
                centerId: classGroup.centerId,
                editable: true,
              ),
            );
          },
        );
      },
    );
  }
}
