import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_service.dart';
import '../models/schedule.dart';

class ScheduleService {
  final SupabaseClient _client;

  ScheduleService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  Future<List<ScheduleEntry>> fetchEntries({
    required String type,
    required String refId,
  }) async {
    final rows = await _client
        .from('schedule_entries')
        .select()
        .eq('type', type)
        .eq('ref_id', refId)
        .order('day')
        .order('start_time');
    return (rows as List)
        .map((row) => ScheduleEntry.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  // Returns the full inserted row (Postgrest already sends it back) so
  // callers can update local state directly instead of re-fetching the
  // whole list right after a write.
  Future<ScheduleEntry> createEntry({
    required String type,
    required String refId,
    required String centerId,
    required String day,
    required String startTime,
    required String endTime,
    required String label,
    required String color,
    String? lessonPlanId,
    required String actorUid,
  }) async {
    final row = await _client.from('schedule_entries').insert({
      'type': type,
      'ref_id': refId,
      'center_id': centerId,
      'day': day,
      'start_time': startTime,
      'end_time': endTime,
      'label': label,
      'color': color,
      'lesson_plan_id': lessonPlanId,
      'created_by': actorUid,
      'updated_by': actorUid,
    }).select().single();
    return ScheduleEntry.fromJson(row);
  }

  // Same reasoning as createEntry: return the updated row instead of
  // making the caller re-fetch to see the change reflected.
  Future<ScheduleEntry> updateEntry({
    required String id,
    required String day,
    required String startTime,
    required String endTime,
    required String label,
    required String color,
    String? lessonPlanId,
    required String actorUid,
  }) async {
    final row = await _client.from('schedule_entries').update({
      'day': day,
      'start_time': startTime,
      'end_time': endTime,
      'label': label,
      'color': color,
      'lesson_plan_id': lessonPlanId,
      'updated_by': actorUid,
    }).eq('id', id).select().single();
    return ScheduleEntry.fromJson(row);
  }

  Future<void> deleteEntry(String id) async {
    await _client.from('schedule_entries').delete().eq('id', id);
  }
}

final scheduleServiceProvider = Provider<ScheduleService>(
  (ref) => ScheduleService(client: ref.watch(supabaseClientProvider)),
);

// A record makes a clean Riverpod family key here — value-equatable by
// default, no extra class needed just to carry (type, refId) together.
typedef ScheduleQuery = ({String type, String refId});

final scheduleEntriesProvider =
    FutureProvider.autoDispose.family<List<ScheduleEntry>, ScheduleQuery>((ref, query) {
  return ref
      .watch(scheduleServiceProvider)
      .fetchEntries(type: query.type, refId: query.refId);
});
