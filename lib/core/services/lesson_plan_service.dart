import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_service.dart';
import '../models/lesson_plan.dart';

// Reads/writes the `lesson_plans` table. RLS: a teacher sees/creates/edits
// their own; a director sees all and can edit/delete/approve any. The DB has
// two UPDATE policies so a teacher can only set draft/submitted (never
// self-approve) -- see the design doc §6.5.
class LessonPlanService {
  final SupabaseClient _client;

  LessonPlanService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // A teacher's own plans, newest first.
  Future<List<LessonPlan>> fetchForTeacher(String teacherId) async {
    final rows = await _client
        .from('lesson_plans')
        .select()
        .eq('teacher_id', teacherId)
        .order('date', ascending: false);
    return (rows as List)
        .map((row) => LessonPlan.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  // All plans (director browse), newest first. RLS returns everything only
  // for a director.
  Future<List<LessonPlan>> fetchAll() async {
    final rows =
        await _client.from('lesson_plans').select().order('date', ascending: false);
    return (rows as List)
        .map((row) => LessonPlan.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  // Teacher creates a plan (always starts as a draft). RLS insert = teacher.
  Future<LessonPlan> createPlan({
    required String title,
    required String date,
    required String content,
    String? subjectId,
    String? classId,
    required String teacherId,
    required String centerId,
    required String actorUid,
  }) async {
    final row = await _client.from('lesson_plans').insert({
      'title': title,
      'date': date,
      'content': content,
      'subject_id': subjectId,
      'class_id': classId,
      'teacher_id': teacherId,
      'center_id': centerId,
      'status': LessonPlanStatus.draft.db,
      'created_by': actorUid,
      'updated_by': actorUid,
    }).select().single();
    return LessonPlan.fromJson(row);
  }

  // Edit the content fields (title/date/subject/class/content). Leaves the
  // status untouched -- transitions go through submit()/review().
  Future<LessonPlan> updatePlan({
    required String id,
    required String title,
    required String date,
    required String content,
    String? subjectId,
    String? classId,
    required String actorUid,
  }) async {
    final row = await _client.from('lesson_plans').update({
      'title': title,
      'date': date,
      'content': content,
      'subject_id': subjectId,
      'class_id': classId,
      'updated_by': actorUid,
    }).eq('id', id).select().single();
    return LessonPlan.fromJson(row);
  }

  // Teacher sends a plan for approval (draft/rejected -> submitted). The
  // teacher UPDATE policy allows setting 'submitted'.
  Future<LessonPlan> submitPlan({required String id, required String actorUid}) async {
    final row = await _client.from('lesson_plans').update({
      'status': LessonPlanStatus.submitted.db,
      'updated_by': actorUid,
    }).eq('id', id).select().single();
    return LessonPlan.fromJson(row);
  }

  // Director approves or rejects a submitted plan, recording who/when and an
  // optional note. Only a director's UPDATE policy permits approved/rejected.
  Future<LessonPlan> reviewPlan({
    required String id,
    required bool approved,
    String? note,
    required String actorUid,
  }) async {
    final row = await _client.from('lesson_plans').update({
      'status': (approved ? LessonPlanStatus.approved : LessonPlanStatus.rejected).db,
      'reviewed_by': actorUid,
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
      'review_note': note,
      'updated_by': actorUid,
    }).eq('id', id).select().single();
    return LessonPlan.fromJson(row);
  }

  // Teacher deletes own, or director deletes any (lesson_plans_delete RLS).
  Future<void> deletePlan(String id) async {
    await _client.from('lesson_plans').delete().eq('id', id);
  }
}

final lessonPlanServiceProvider = Provider<LessonPlanService>(
  (ref) => LessonPlanService(client: ref.watch(supabaseClientProvider)),
);
