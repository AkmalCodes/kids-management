import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_service.dart';
import '../models/daily_report.dart';

// One report per child per day (UNIQUE child_id,date). Teachers write for
// their class; parents read their child's; directors read all -- enforced
// by daily_reports RLS. Report photos live in the private
// 'daily-report-images' bucket.
class DailyReportService {
  final SupabaseClient _client;

  DailyReportService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // Newest first -- the parent's feed for a child.
  Future<List<DailyReport>> fetchForChild(String childId) async {
    final rows = await _client
        .from('daily_reports')
        .select()
        .eq('child_id', childId)
        .order('date', ascending: false)
        .limit(60);
    return (rows as List)
        .map((row) => DailyReport.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  // The existing report for a child on a day, or null -- so the teacher's
  // editor pre-fills instead of creating a duplicate.
  Future<DailyReport?> fetchForChildAndDate(String childId, String date) async {
    final rows = await _client
        .from('daily_reports')
        .select()
        .eq('child_id', childId)
        .eq('date', date)
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    return DailyReport.fromJson(list.first as Map<String, dynamic>);
  }

  // existingId absent -> insert; present -> update (preserving created_by),
  // same pattern as markAttendance. Returns the saved row.
  Future<DailyReport> saveReport({
    required String childId,
    required String teacherId,
    required String centerId,
    required String date,
    required String text,
    required List<String> imagePaths,
    required String actorUid,
    String? existingId,
  }) async {
    final payload = {
      'child_id': childId,
      'teacher_id': teacherId,
      'center_id': centerId,
      'date': date,
      'text': text,
      'image_paths': imagePaths,
      'updated_by': actorUid,
      if (existingId == null) 'created_by': actorUid,
    };
    final row = existingId != null
        ? await _client.from('daily_reports').update(payload).eq('id', existingId).select().single()
        : await _client.from('daily_reports').insert(payload).select().single();
    return DailyReport.fromJson(row);
  }

  // Each image gets a unique path under the child+day so multiple photos in
  // one report don't collide.
  Future<String> uploadReportImage({
    required String childId,
    required String date,
    required XFile photo,
  }) async {
    final path = '$childId/$date/${DateTime.now().microsecondsSinceEpoch}.jpg';
    final bytes = await photo.readAsBytes();
    await _client.storage.from('daily-report-images').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    return path;
  }

  Future<String> getSignedReportImageUrl(String path) =>
      _client.storage.from('daily-report-images').createSignedUrl(path, 3600);
}

final dailyReportServiceProvider = Provider<DailyReportService>(
  (ref) => DailyReportService(client: ref.watch(supabaseClientProvider)),
);

// Session-cached signed URL for a report image path.
final signedReportImageUrlProvider = FutureProvider.family<String, String>((ref, path) {
  return ref.watch(dailyReportServiceProvider).getSignedReportImageUrl(path);
});
