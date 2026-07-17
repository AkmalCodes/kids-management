import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_service.dart';
import '../models/attendance.dart';

class AttendanceService {
  final SupabaseClient _client;

  AttendanceService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  Future<List<Attendance>> fetchForChild(String childId) async {
    final rows = await _client
        .from('attendance')
        .select()
        .eq('child_id', childId)
        .order('date', ascending: false)
        .limit(30);
    return (rows as List)
        .map((row) => Attendance.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<Attendance>> fetchForDate(String date) async {
    final rows = await _client.from('attendance').select().eq('date', date);
    return (rows as List)
        .map((row) => Attendance.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  // existingId absent -> insert; existingId present -> update, preserving
  // the original created_by (same pattern as ScheduleService.saveSchedule).
  Future<void> markAttendance({
    required String childId,
    required String centerId,
    required String date,
    required AttendanceStatus status,
    required String actorUid,
    String? existingId,
    String notes = '',
  }) async {
    final payload = {
      'child_id': childId,
      'center_id': centerId,
      'date': date,
      'status': status.name,
      'notes': notes,
      'updated_by': actorUid,
      if (existingId == null) 'created_by': actorUid,
    };
    if (existingId != null) {
      await _client.from('attendance').update(payload).eq('id', existingId);
    } else {
      await _client.from('attendance').insert(payload);
    }
  }
}

final attendanceServiceProvider = Provider<AttendanceService>(
  (ref) => AttendanceService(client: ref.watch(supabaseClientProvider)),
);
