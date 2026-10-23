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

  // One staff member's rows between two dates (inclusive, YYYY-MM-DD), oldest
  // first -- the clock screen's "This week" list. Read-only. RLS already
  // limits a teacher to their own rows (staff_attendance_select), so the
  // staff_id filter is for correctness, not the security boundary.
  Future<List<StaffAttendance>> fetchForStaffBetween({
    required String staffId,
    required String from,
    required String to,
  }) async {
    final rows = await _client
        .from('staff_attendance')
        .select()
        .eq('staff_id', staffId)
        .gte('date', from)
        .lte('date', to)
        .order('date');
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
  // (existingId). Sets status 'present' and clock_in_at = [at]. A separate,
  // explicitly named method rather than nullable params on markAttendance --
  // matches this project's attachCheckInPhoto/attachBelongingsPhoto convention
  // and keeps the precondition ("no clock time recorded yet") in the signature.
  //
  // [at] is passed in (not read from DateTime.now() here) so the recorded value
  // is exactly the one the teacher saw and confirmed on screen -- this is
  // payroll data, so the confirm dialog and the stored row must not drift.
  Future<StaffAttendance> clockIn({
    required String staffId,
    required String centerId,
    required String date,
    required String actorUid,
    required DateTime at,
    String? existingId,
  }) async {
    // UTC ISO-8601 -- Postgres TIMESTAMPTZ stores an absolute instant; the UI
    // calls .toLocal() when it displays the time.
    final nowIso = at.toUtc().toIso8601String();
    final payload = {
      'staff_id': staffId,
      'center_id': centerId,
      'date': date,
      'status': AttendanceStatus.present.name,
      'clock_in_at': nowIso,
      'updated_by': actorUid,
      if (existingId == null) 'created_by': actorUid,
    };
    // UPDATE path: guard that clock_in_at IS still null. The DB CHECK enforces
    // clock_out > clock_in ordering only, never immutability, so a stale second
    // screen could otherwise silently overwrite an earlier start time. With
    // .single() on the chain, zero matched rows throws -> the screen's catch
    // turns it into a visible "Could not clock in" SnackBar instead of data
    // loss. The INSERT path needs no such guard: UNIQUE (staff_id, date) covers
    // it. isFilter('col', null) emits `col=is.null` (postgrest 2.8.0).
    final row = existingId != null
        ? await _client
            .from('staff_attendance')
            .update(payload)
            .eq('id', existingId)
            .isFilter('clock_in_at', null)
            .select()
            .single()
        : await _client.from('staff_attendance').insert(payload).select().single();
    return StaffAttendance.fromJson(row);
  }

  // Records the end of the day. Only ever updates an existing row -- clocking
  // out with nothing to clock out of is a UI-level impossibility (the button
  // only exists once a row with clock_in_at exists), and the DB CHECK
  // constraint would reject clock_out_at with a null clock_in_at anyway.
  //
  // [at] is passed in for the same reason as clockIn: the stored time must be
  // the one the teacher confirmed, not a fresh now().
  Future<StaffAttendance> clockOut({
    required String id,
    required String actorUid,
    required DateTime at,
  }) async {
    // Guard that clock_out_at IS still null, same rationale as clockIn's UPDATE
    // guard: turn a stale double clock-out into a thrown error the screen
    // surfaces, not a silent overwrite of the recorded end time.
    final row = await _client
        .from('staff_attendance')
        .update({
          'clock_out_at': at.toUtc().toIso8601String(),
          'updated_by': actorUid,
        })
        .eq('id', id)
        .isFilter('clock_out_at', null)
        .select()
        .single();
    return StaffAttendance.fromJson(row);
  }
}

final staffAttendanceControllerProvider = Provider<StaffAttendanceController>(
  (ref) => StaffAttendanceController(client: ref.watch(supabaseClientProvider)),
);
