import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_service.dart';
import '../models/class_group.dart';

// Reads from the `classes` table. RLS lets directors see all, teachers see
// their own, and parents see the class their child is in.
class ClassService {
  final SupabaseClient _client;

  ClassService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // For the director's Schedules tab (pick a class to edit its schedule).
  Future<List<ClassGroup>> fetchAll() async {
    final rows = await _client.from('classes').select().order('name');
    return (rows as List)
        .map((row) => ClassGroup.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  // Classes this teacher is assigned to (their own schedule = their class's).
  Future<List<ClassGroup>> fetchForTeacher(String teacherId) async {
    final rows =
        await _client.from('classes').select().eq('teacher_uid', teacherId).order('name');
    return (rows as List)
        .map((row) => ClassGroup.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  // Resolve one class (e.g. to find its teacher for the parent's schedule).
  Future<ClassGroup?> getClass(String id) async {
    final rows = await _client.from('classes').select().eq('id', id).limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    return ClassGroup.fromJson(list.first as Map<String, dynamic>);
  }

  // Director-only (classes_insert/update RLS). Return the saved row.
  Future<ClassGroup> createClass({
    required String name,
    required String? teacherId,
    required String centerId,
    required String actorUid,
  }) async {
    final row = await _client.from('classes').insert({
      'name': name,
      'teacher_uid': teacherId,
      'center_id': centerId,
      'created_by': actorUid,
      'updated_by': actorUid,
    }).select().single();
    return ClassGroup.fromJson(row);
  }

  Future<ClassGroup> updateClass({
    required String id,
    required String name,
    required String? teacherId,
    required String actorUid,
  }) async {
    final row = await _client.from('classes').update({
      'name': name,
      'teacher_uid': teacherId,
      'updated_by': actorUid,
    }).eq('id', id).select().single();
    return ClassGroup.fromJson(row);
  }

  // Class photo lives in a private 'class-avatars' bucket, one file per class
  // at '<class_id>/avatar.jpg' -- same private-bucket + signed-URL pattern as
  // child avatars. Deterministic path so a replacement overwrites (upsert).
  Future<String> uploadClassAvatar({required String classId, required XFile photo}) async {
    final path = '$classId/avatar.jpg';
    final bytes = await photo.readAsBytes();
    await _client.storage.from('class-avatars').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
    return path;
  }

  // Director-only (classes_update RLS): writes the avatar path onto the class.
  Future<void> setClassAvatarPath({
    required String classId,
    required String path,
    required String actorUid,
  }) async {
    await _client.from('classes').update({
      'avatar_path': path,
      'updated_by': actorUid,
    }).eq('id', classId);
  }

  Future<String> getSignedClassAvatarUrl(String path) =>
      _client.storage.from('class-avatars').createSignedUrl(path, 3600);
}

final classServiceProvider = Provider<ClassService>(
  (ref) => ClassService(client: ref.watch(supabaseClientProvider)),
);

// Resolves a single class by id (cached per id). Used to look up the
// class's teacher for the parent's schedule view.
final classGroupProvider = FutureProvider.family<ClassGroup?, String>((ref, id) {
  return ref.watch(classServiceProvider).getClass(id);
});

// Session-cached signed URL for a class avatar path (same pattern as
// signedChildAvatarUrlProvider, but for the class-avatars bucket).
final signedClassAvatarUrlProvider = FutureProvider.family<String, String>((ref, path) {
  return ref.watch(classServiceProvider).getSignedClassAvatarUrl(path);
});
