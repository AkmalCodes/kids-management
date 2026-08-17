import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/controllers/profile_controller.dart';
import '../../../core/controllers/schedule_controller.dart';
import '../../../shared/widgets/schedule_agenda_view.dart';
import '../../../shared/widgets/signed_avatar.dart';
import '../../../shared/widgets/app_loader.dart';

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
    this.avatarPath,
  });

  final String title;
  final String type;
  final String refId;
  final String? centerId;
  // Optional user avatar (from the 'avatars' bucket) shown beside the title
  // -- passed for teachers; null for children.
  final String? avatarPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(scheduleEntriesProvider((type: type, refId: refId)));

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (avatarPath != null) ...[
              SignedAvatar(urlProvider: signedAvatarUrlProvider(avatarPath!), radius: 16),
              const SizedBox(width: 8),
            ],
            Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
      body: entriesAsync.when(
        loading: () => const Center(child: AppLoader()),
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
