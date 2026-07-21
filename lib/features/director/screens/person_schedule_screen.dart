import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/schedule_service.dart';
import '../../../shared/widgets/schedule_agenda_view.dart';

// Landed on from DirectorSchedulesScreen after picking a teacher or child.
// Always editable=true: a director can create/edit/delete any schedule,
// per the schedule_entries RLS policies.
class PersonScheduleScreen extends ConsumerWidget {
  const PersonScheduleScreen({
    super.key,
    required this.title,
    required this.type,
    required this.refId,
    required this.centerId,
  });

  final String title;
  final String type;
  final String refId;
  final String? centerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(scheduleEntriesProvider((type: type, refId: refId)));

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (entries) => ScheduleAgendaView(
          entries: entries,
          type: type,
          refId: refId,
          centerId: centerId,
          editable: true,
        ),
      ),
    );
  }
}
