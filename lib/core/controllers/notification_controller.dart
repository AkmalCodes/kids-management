import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_controller.dart';
import '../models/app_notification.dart';

// Reads/writes the `notifications` table. RLS: a user sees/updates only
// their own rows. Rows are never inserted by the app -- only by the
// `lesson_plan_status_notify` Postgres trigger (SECURITY DEFINER), so
// there's no createNotification method here. See the design doc.
class NotificationController {
  final SupabaseClient _client;

  NotificationController({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // Live list for one user, newest first. Realtime (`.stream()`) merges an
  // initial fetch with live INSERT/UPDATE/DELETE events -- this is the
  // first use of it in the codebase (see the migration's
  // ALTER PUBLICATION step, required for this to ever emit anything).
  //
  // The `.eq('user_id', ...)` filter is for efficiency, not security: RLS
  // already hides other users' rows, and Realtime respects RLS too.
  Stream<List<AppNotification>> watchNotifications(String userId) {
    return _client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map(AppNotification.fromJson).toList());
  }

  // Only patches read_at; the UPDATE policy's WITH CHECK keeps user_id
  // pinned to the caller, so this can't be abused to touch others' rows.
  Future<void> markRead(String id) => _client
      .from('notifications')
      .update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
}

final notificationControllerProvider = Provider<NotificationController>(
  (ref) => NotificationController(client: ref.watch(supabaseClientProvider)),
);

// Empty stream while signed out/loading -- switches to the real live stream
// the moment currentUserProvider resolves to a user, and back to empty on
// sign-out (ref.watch rebuilds this provider on every AsyncValue change).
final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final user = ref.watch(currentUserProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(notificationControllerProvider).watchNotifications(user.id);
});

// Convenience for the bell badge -- recomputed on every notificationsProvider
// emission either way, so this exists for readability at the call site, not
// as a performance optimization.
final unreadNotificationsCountProvider = Provider<int>((ref) {
  final notifications = ref.watch(notificationsProvider).value ?? const [];
  return notifications.where((n) => n.readAt == null).length;
});
