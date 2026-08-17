import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/models/child.dart';
import '../../../core/controllers/child_controller.dart';
import '../../../core/controllers/schedule_controller.dart';
import '../../../shared/widgets/schedule_agenda_view.dart';
import '../../../shared/widgets/signed_avatar.dart';
import '../../../shared/widgets/app_loader.dart';

class ChildScheduleScreen extends ConsumerWidget {
  const ChildScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    return userAsync.when(
      loading: () => const Center(child: AppLoader()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (user) {
        if (user == null) return const SizedBox.shrink();
        return FutureBuilder<List<Child>>(
          future: ref.read(childControllerProvider).fetchForParent(user.id),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: AppLoader());
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
        _scheduleBody(context, ref),
      ],
    );
  }

  // The schedule belongs to the child's class (§6.8). Parent views it
  // read-only: child -> class_id -> that class's schedule entries.
  Widget _scheduleBody(BuildContext context, WidgetRef ref) {
    if (child.classId == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Not assigned to a class yet.'),
      );
    }
    final entriesAsync = ref.watch(scheduleEntriesProvider((type: 'class', refId: child.classId!)));
    return entriesAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: AppLoader()),
      ),
      error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text('Error: $e')),
      // editable defaults to false: parents only ever view.
      data: (entries) => ScheduleAgendaView(entries: entries, shrinkWrap: true),
    );
  }
}
