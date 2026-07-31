import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_service.dart';
import '../models/subject.dart';

// Reads/writes the `subjects` table. RLS lets any authenticated user read
// (subjects show up on lesson plans and the schedule), but only directors
// create/edit/delete them.
class SubjectService {
  final SupabaseClient _client;

  SubjectService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  Future<List<Subject>> fetchAll() async {
    final rows = await _client.from('subjects').select().order('name');
    return (rows as List)
        .map((row) => Subject.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  // Director-only (subjects_insert RLS). Returns the saved row.
  Future<Subject> createSubject({
    required String name,
    String? color,
    required String centerId,
    required String actorUid,
  }) async {
    final row = await _client.from('subjects').insert({
      'name': name,
      'color': color,
      'center_id': centerId,
      'created_by': actorUid,
      'updated_by': actorUid,
    }).select().single();
    return Subject.fromJson(row);
  }

  Future<Subject> updateSubject({
    required String id,
    required String name,
    String? color,
    required String actorUid,
  }) async {
    final row = await _client.from('subjects').update({
      'name': name,
      'color': color,
      'updated_by': actorUid,
    }).eq('id', id).select().single();
    return Subject.fromJson(row);
  }

  // Director-only (subjects_delete RLS). Lesson plans reference subject_id
  // with ON DELETE SET NULL, so removing a subject just un-tags its plans.
  Future<void> deleteSubject(String id) async {
    await _client.from('subjects').delete().eq('id', id);
  }
}

final subjectServiceProvider = Provider<SubjectService>(
  (ref) => SubjectService(client: ref.watch(supabaseClientProvider)),
);
