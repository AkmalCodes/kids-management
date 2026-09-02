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
}

final staffAttendanceControllerProvider = Provider<StaffAttendanceController>(
  (ref) => StaffAttendanceController(client: ref.watch(supabaseClientProvider)),
);
