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

  // A teacher's own plans, newest first. (Ordered by created_at now that
  // plans have no date -- they're reusable.)
  Future<List<LessonPlan>> fetchForTeacher(String teacherId) async {
    final rows = await _client
        .from('lesson_plans')
        .select()
        .eq('teacher_id', teacherId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((row) => LessonPlan.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  // All plans (director browse), newest first. RLS returns everything only
  // for a director.
  Future<List<LessonPlan>> fetchAll() async {
    final rows =
        await _client.from('lesson_plans').select().order('created_at', ascending: false);
    return (rows as List)
        .map((row) => LessonPlan.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  // Teacher creates a plan (always starts as a draft). RLS insert = teacher.
  // Plans are reusable (no date) -- they're attached to schedule events.
  Future<LessonPlan> createPlan({
    required String title,
    required String content,
    String? subjectId,
    String? classId,
    required String teacherId,
    required String centerId,
    required String actorUid,
  }) async {
    final row = await _client.from('lesson_plans').insert({
      'title': title,
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

  // Edit the content fields (title/subject/class/content). Leaves the status
  // untouched -- transitions go through submit()/review().
  Future<LessonPlan> updatePlan({
    required String id,
    required String title,
    required String content,
    String? subjectId,
    String? classId,
    required String actorUid,
  }) async {
    final row = await _client.from('lesson_plans').update({
      'title': title,
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

  // The approved plans for a class, for the schedule event's lesson-plan
  // picker and for resolving the subject shown on an event (§6.5 increment
  // 2). RLS lets the class's teacher, a parent of a child in the class, and
  // the director read approved plans -- so parents can open the attached
  // plan from the schedule.
  Future<List<LessonPlan>> fetchApprovedForClass(String classId) async {
    final rows = await _client
        .from('lesson_plans')
        .select()
        .eq('class_id', classId)
        .eq('status', LessonPlanStatus.approved.db)
        .order('title');
    return (rows as List)
        .map((row) => LessonPlan.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  // plan id -> subject label for a class's approved plans, for showing the
  // subject on schedule events to EVERY role. Goes through the
  // `class_plan_subjects` SECURITY DEFINER function, which returns only the
  // (approved) plan id + title + subject to a viewer connected to the class
  // (director, the class's teacher, or a parent of a child in it) -- so the
  // label resolves for parents without depending on the lesson_plans row
  // being directly readable to them.
  Future<List<PlanSubject>> fetchClassPlanSubjects(String classId) async {
    final rows = await _client.rpc('class_plan_subjects', params: {'p_class_id': classId});
    return (rows as List)
        .map((r) => PlanSubject(
              id: (r as Map)['plan_id'] as String,
              title: r['title'] as String,
              subject: r['subject_name'] as String?,
            ))
        .toList();
  }

  // One plan by id (for opening an attached plan). Returns null if the caller
  // can't see it under RLS.
  Future<LessonPlan?> getPlan(String id) async {
    final rows = await _client.from('lesson_plans').select().eq('id', id).limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    return LessonPlan.fromJson(list.first as Map<String, dynamic>);
  }
}

// The subject/title label for an approved plan attached to a schedule event,
// visible to any role connected to the class (no content -- see
// fetchClassPlanSubjects).
class PlanSubject {
  const PlanSubject({required this.id, required this.title, required this.subject});
  final String id;
  final String title;
  final String? subject;
}

final lessonPlanServiceProvider = Provider<LessonPlanService>(
  (ref) => LessonPlanService(client: ref.watch(supabaseClientProvider)),
);
