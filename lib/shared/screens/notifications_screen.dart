import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/controllers/lesson_plan_controller.dart';
import '../../core/controllers/notification_controller.dart';
import '../../core/models/app_notification.dart';
import '../../features/shared_lessons/lesson_plan_edit_screen.dart';
import '../widgets/app_loader.dart';

// Full-screen notification list, reachable from both TeacherShell and
// DirectorShell (see NotificationBellAction). `isDirector` is passed in
// from the shell -- same pattern LessonPlanEditScreen already uses -- so
// this screen never needs to look up the caller's role itself.
//
// No manual refresh needed: notificationsProvider is a Realtime stream, so
// marking a row read (or a new trigger insert) re-emits and this rebuilds.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key, required this.isDirector});

  final bool isDirector;

  Future<void> _open(BuildContext context, WidgetRef ref, AppNotification n) async {
    // Skip the write if it's already read -- avoids a pointless UPDATE that
    // would also bump read_at to "now" every time an old row is reopened.
    if (n.readAt == null) {
      await ref.read(notificationControllerProvider).markRead(n.id);
    }
    // Only 'lesson_plan' exists today, but this switch is how a second
    // entity type gets added later without a rewrite.
    switch (n.type) {
      case 'lesson_plan':
        final plan = await ref.read(lessonPlanControllerProvider).getPlan(n.entityId);
        // An `await` happened, so the screen may have been popped meanwhile;
        // using a dead context would throw.
        if (!context.mounted) return;
        if (plan == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('That lesson plan no longer exists.')),
          );
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LessonPlanEditScreen(plan: plan, isDirector: isDirector),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: notificationsAsync.when(
        loading: () => const Center(child: AppLoader()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (notifications) {
          if (notifications.isEmpty) {
            return const Center(child: Text('No notifications yet.'));
          }
          return ListView.builder(
            itemCount: notifications.length,
            itemBuilder: (context, i) {
              final n = notifications[i];
              final unread = n.readAt == null;
              return ListTile(
                // Small dot marks unread; the SizedBox keeps read rows'
                // titles aligned with unread ones.
                leading: unread
                    ? Icon(Icons.circle, size: 10, color: Theme.of(context).colorScheme.error)
                    : const SizedBox(width: 10),
                title: Text(
                  n.title,
                  style: TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.normal),
                ),
                // For a rejection, body already carries the director's
                // review_note (folded in by the DB trigger).
                subtitle: Text(n.body),
                onTap: () => _open(context, ref, n),
              );
            },
          );
        },
      ),
    );
  }
}
