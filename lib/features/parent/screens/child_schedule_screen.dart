import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/models/child.dart';
import '../../../core/services/child_service.dart';
import '../../../core/services/schedule_service.dart';
import '../../../shared/widgets/schedule_agenda_view.dart';

class ChildScheduleScreen extends ConsumerWidget {
  const ChildScheduleScreen({super.key});

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
                for (final child in children) _ChildScheduleSection(child: child),
              ],
            );
          },
        );
      },
    );
  }
}

class _ChildScheduleSection extends ConsumerWidget {
  const _ChildScheduleSection({required this.child});

  final Child child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(scheduleEntriesProvider((type: 'child', refId: child.id)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(child.name, style: Theme.of(context).textTheme.titleLarge),
        ),
        entriesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Error: $e'),
          ),
          // editable defaults to false: parents never edit a child's
          // schedule, only the director (per the RBAC design) or a teacher.
          data: (entries) => ScheduleAgendaView(entries: entries, shrinkWrap: true),
        ),
      ],
    );
  }
}
