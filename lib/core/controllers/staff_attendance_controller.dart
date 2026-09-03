import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_controller.dart';
import '../models/attendance.dart';
import '../models/staff_attendance.dart';

class StaffAttendanceController {
  final SupabaseClient _client;

  StaffAttendanceController({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // All staff rows for a date, unfiltered by staff -- mirrors
  // AttendanceController.fetchForDate. A director's future roster view
  // fetches once and filters client-side by staff_id, same pattern
  // mark_attendance_screen.dart already uses for children.
  Future<List<StaffAttendance>> fetchForDate(String date) async {
    final rows = await _client.from('staff_attendance').select().eq('date', date);
    return (rows as List)
        .map((row) => StaffAttendance.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  // existingId absent -> insert; existingId present -> update, preserving
  // the original created_by. Same pattern as AttendanceController.markAttendance,
  // minus photo-column preservation -- there are no photo columns here.
  Future<StaffAttendance> markAttendance({
    required String staffId,
    required String centerId,
    required String date,
    required AttendanceStatus status,
    required String actorUid,
    String? existingId,
    String notes = '',
  }) async {
    final payload = {
      'staff_id': staffId,
      'center_id': centerId,
      'date': date,
      'status': status.name,
      'notes': notes,
      'updated_by': actorUid,
      if (existingId == null) 'created_by': actorUid,
    };
    final row = existingId != null
        ? await _client.from('staff_attendance').update(payload).eq('id', existingId).select().single()
        : await _client.from('staff_attendance').insert(payload).select().single();
    return StaffAttendance.fromJson(row);
  }

  // Records the start of a teacher's working day. Creates today's row if none
  // exists yet, or updates one a director already created for this teacher
  // (existingId). Sets status 'present' and clock_in_at = now. A separate,
  // explicitly named method rather than nullable params on markAttendance --
  // matches this project's attachCheckInPhoto/attachBelongingsPhoto convention
  // and keeps the precondition ("no clock time recorded yet") in the signature.
  Future<StaffAttendance> clockIn({
    required String staffId,
    required String centerId,
    required String date,
    required String actorUid,
    String? existingId,
  }) async {
    // UTC ISO-8601 -- Postgres TIMESTAMPTZ stores an absolute instant; the UI
    // calls .toLocal() when it displays the time.
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final payload = {
      'staff_id': staffId,
      'center_id': centerId,
      'date': date,
      'status': AttendanceStatus.present.name,
      'clock_in_at': nowIso,
      'updated_by': actorUid,
      if (existingId == null) 'created_by': actorUid,
    };
    final row = existingId != null
        ? await _client.from('staff_attendance').update(payload).eq('id', existingId).select().single()
        : await _client.from('staff_attendance').insert(payload).select().single();
    return StaffAttendance.fromJson(row);
  }

  // Records the end of the day. Only ever updates an existing row -- clocking
  // out with nothing to clock out of is a UI-level impossibility (the button
  // only exists once a row with clock_in_at exists), and the DB CHECK
  // constraint would reject clock_out_at with a null clock_in_at anyway.
  Future<StaffAttendance> clockOut({
    required String id,
    required String actorUid,
  }) async {
    final row = await _client
        .from('staff_attendance')
        .update({
          'clock_out_at': DateTime.now().toUtc().toIso8601String(),
          'updated_by': actorUid,
        })
        .eq('id', id)
        .select()
        .single();
    return StaffAttendance.fromJson(row);
  }
}

final staffAttendanceControllerProvider = Provider<StaffAttendanceController>(
  (ref) => StaffAttendanceController(client: ref.watch(supabaseClientProvider)),
);
