import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_service.dart';
import '../models/schedule.dart';

class ScheduleService {
  final SupabaseClient _client;

  ScheduleService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  Future<Schedule?> fetchSchedule({
    required String type,
    required String refId,
  }) async {
    final rows = await _client
        .from('schedules')
        .select()
        .eq('type', type)
        .eq('ref_id', refId)
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    return Schedule.fromJson(list.first as Map<String, dynamic>);
  }

  // existingId absent -> insert (created_by set once); existingId present ->
  // update (created_by omitted from the payload so the original creator is
  // preserved, only updated_by/updated_at change).
  Future<void> saveSchedule({
    required String type,
    required String refId,
    required String centerId,
    required List<ScheduleEntry> entries,
    required String actorUid,
    String? existingId,
  }) async {
    final payload = {
      'type': type,
      'ref_id': refId,
      'center_id': centerId,
      'entries': entries.map((e) => e.toJson()).toList(),
      'updated_by': actorUid,
      if (existingId == null) 'created_by': actorUid,
    };
    if (existingId != null) {
      await _client.from('schedules').update(payload).eq('id', existingId);
    } else {
      await _client.from('schedules').insert(payload);
    }
  }
}

final scheduleServiceProvider = Provider<ScheduleService>(
  (ref) => ScheduleService(client: ref.watch(supabaseClientProvider)),
);

// A record makes a clean Riverpod family key here — value-equatable by
// default, no extra class needed just to carry (type, refId) together.
typedef ScheduleQuery = ({String type, String refId});

final scheduleProvider =
    FutureProvider.autoDispose.family<Schedule?, ScheduleQuery>((ref, query) {
  return ref
      .watch(scheduleServiceProvider)
      .fetchSchedule(type: query.type, refId: query.refId);
});
