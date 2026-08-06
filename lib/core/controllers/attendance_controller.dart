import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_controller.dart';
import '../models/attendance.dart';

class AttendanceController {
  final SupabaseClient _client;

  AttendanceController({SupabaseClient? client})
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
  // the original created_by (same pattern as ScheduleController.saveSchedule).
  // Deliberately doesn't touch photo_path/belongings_photo_path -- those
  // are attached independently via attachCheckInPhoto/attachBelongingsPhoto
  // so changing status never silently wipes out a photo someone attached
  // earlier.
  // Returns the saved row (via .select().single()) so the caller can
  // update its local state directly instead of re-fetching the whole
  // roster -- same round-trip-avoidance as ScheduleController's create/update.
  Future<Attendance> markAttendance({
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
    final row = existingId != null
        ? await _client.from('attendance').update(payload).eq('id', existingId).select().single()
        : await _client.from('attendance').insert(payload).select().single();
    return Attendance.fromJson(row);
  }

  // Both photo attachments require an existing attendance record (the UI
  // only enables the camera buttons once a status has been picked for the
  // day), so these are always a plain update of one column -- no
  // insert-vs-update branching needed.

  Future<Attendance> attachCheckInPhoto({
    required String id,
    required String photoPath,
    required String actorUid,
  }) async {
    final row = await _client.from('attendance').update({
      'photo_path': photoPath,
      'updated_by': actorUid,
    }).eq('id', id).select().single();
    return Attendance.fromJson(row);
  }

  Future<Attendance> attachBelongingsPhoto({
    required String id,
    required String belongingsPhotoPath,
    required String actorUid,
  }) async {
    final row = await _client.from('attendance').update({
      'belongings_photo_path': belongingsPhotoPath,
      'updated_by': actorUid,
    }).eq('id', id).select().single();
    return Attendance.fromJson(row);
  }

  // Removes both the stored file and the column reference -- leaving the
  // file behind would just be an orphaned object nobody can reach once the
  // column is cleared.
  Future<Attendance> removeCheckInPhoto({
    required String id,
    required String photoPath,
    required String actorUid,
  }) async {
    await _client.storage.from('attendance-photos').remove([photoPath]);
    final row = await _client.from('attendance').update({
      'photo_path': null,
      'updated_by': actorUid,
    }).eq('id', id).select().single();
    return Attendance.fromJson(row);
  }

  Future<Attendance> removeBelongingsPhoto({
    required String id,
    required String belongingsPhotoPath,
    required String actorUid,
  }) async {
    await _client.storage.from('attendance-photos').remove([belongingsPhotoPath]);
    final row = await _client.from('attendance').update({
      'belongings_photo_path': null,
      'updated_by': actorUid,
    }).eq('id', id).select().single();
    return Attendance.fromJson(row);
  }

  // Deterministic path per child+day so retaking a photo overwrites (via
  // upsert) rather than accumulating old photos. The two kinds use a
  // distinct suffix so they never collide in Storage.
  Future<String> uploadCheckInPhoto({
    required String childId,
    required String date,
    required XFile photo,
  }) async {
    final path = '$childId/$date.jpg';
    final bytes = await photo.readAsBytes();
    await _client.storage.from('attendance-photos').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
    return path;
  }

  Future<String> uploadBelongingsPhoto({
    required String childId,
    required String date,
    required XFile photo,
  }) async {
    final path = '$childId/$date-belongings.jpg';
    final bytes = await photo.readAsBytes();
    await _client.storage.from('attendance-photos').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
    return path;
  }

  // The bucket is private, so a stored path isn't directly viewable —
  // exchange it for a time-limited signed URL each time it's displayed.
  Future<String> getSignedPhotoUrl(String path) {
    return _client.storage.from('attendance-photos').createSignedUrl(path, 3600);
  }
}

final attendanceControllerProvider = Provider<AttendanceController>(
  (ref) => AttendanceController(client: ref.watch(supabaseClientProvider)),
);
