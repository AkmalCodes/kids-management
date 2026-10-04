import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/controllers/notification_controller.dart';
import '../screens/notifications_screen.dart';

// Bell + unread-count badge, dropped into a shell's AppBar actions.
// `isDirector` is hardcoded by the caller (TeacherShell: false,
// DirectorShell: true) -- same pattern LessonPlanEditScreen's call sites
// already use -- rather than looked up at runtime here.
//
// Because unreadNotificationsCountProvider derives from a Realtime stream,
// the badge updates live: a teacher submitting a plan makes the director's
// count tick up without any refresh.
class NotificationBellAction extends ConsumerWidget {
  const NotificationBellAction({super.key, required this.isDirector});

  final bool isDirector;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadNotificationsCountProvider);
    return IconButton(
      tooltip: 'Notifications',
      // Badge is Material 3's built-in red count bubble; isLabelVisible
      // hides it entirely at 0 instead of showing a "0".
      icon: Badge(
        label: Text('$unreadCount'),
        isLabelVisible: unreadCount > 0,
        child: const Icon(Icons.notifications_outlined),
      ),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => NotificationsScreen(isDirector: isDirector)),
      ),
    );
  }
}
