import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_service.dart';
import '../models/app_user.dart';
import '../models/child.dart';

class ChildService {
  final SupabaseClient _client;

  ChildService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // Unfiltered — relies on the children_select RLS policy to grant
  // directors full read access; teachers/parents calling this would only
  // get back rows they're already allowed to see.
  Future<List<Child>> fetchAll() async {
    final rows = await _client.from('children').select().order('name');
    return (rows as List)
        .map((row) => Child.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<Child>> fetchForTeacher(String teacherId) async {
    final rows = await _client
        .from('children')
        .select()
        .eq('teacher_id', teacherId)
        .order('name');
    return (rows as List)
        .map((row) => Child.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  // children_parents is a join table, so the actual child rows come back
  // nested under the 'children' key — Postgrest's embedded-resource syntax
  // for following a foreign key from the table you queried.
  Future<List<Child>> fetchForParent(String parentId) async {
    final rows = await _client
        .from('children_parents')
        .select('children(*)')
        .eq('parent_id', parentId);
    return (rows as List)
        .map((row) => Child.fromJson(row['children'] as Map<String, dynamic>))
        .toList();
  }

  // Director-only per the children_insert RLS policy. Returns the saved
  // row (with its generated id) so the caller can immediately use it --
  // e.g. to link an invited parent to this child.
  Future<Child> createChild(Child child) async {
    final row = await _client.from('children').insert(child.toJson()).select().single();
    return Child.fromJson(row);
  }

  // Director-only per the children_update RLS policy. Returns the saved row
  // so the caller can update local state directly.
  Future<Child> updateChild(Child child) async {
    final row = await _client
        .from('children')
        .update(child.toJson())
        .eq('id', child.id)
        .select()
        .single();
    return Child.fromJson(row);
  }

  // Child photos live in the private 'child-avatars' bucket (children have
  // no auth account, so they can't use the user 'avatars' bucket), one file
  // per child at '<child_id>/avatar.jpg'.
  Future<String> uploadChildAvatar({required String childId, required XFile photo}) async {
    final path = '$childId/avatar.jpg';
    final bytes = await photo.readAsBytes();
    await _client.storage.from('child-avatars').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
    return path;
  }

  // Director-only: writes just the avatar path (immediate, independent of
  // the detail form's Save), per children_update RLS.
  Future<void> setChildAvatarPath({
    required String childId,
    required String path,
    required String actorUid,
  }) async {
    await _client.from('children').update({
      'avatar_path': path,
      'updated_by': actorUid,
    }).eq('id', childId);
  }

  Future<String> getSignedChildAvatarUrl(String path) =>
      _client.storage.from('child-avatars').createSignedUrl(path, 3600);

  // The parents linked to a child, for the director's child-detail contacts
  // section. Done as two queries because children_parents.parent_id points
  // at auth.users (not profiles), so Postgrest can't embed profiles across
  // it directly -- fetch the ids, then the profile rows.
  Future<List<AppUser>> fetchParentsForChild(String childId) async {
    final links = await _client
        .from('children_parents')
        .select('parent_id')
        .eq('child_id', childId);
    final ids = (links as List).map((l) => l['parent_id'] as String).toList();
    if (ids.isEmpty) return [];
    final rows = await _client.from('profiles').select().inFilter('id', ids);
    return (rows as List)
        .map((row) => AppUser.fromJson(row as Map<String, dynamic>))
        .toList();
  }
}

final childServiceProvider = Provider<ChildService>(
  (ref) => ChildService(client: ref.watch(supabaseClientProvider)),
);

// Session-cached signed URL for a child avatar path (same pattern as
// signedAvatarUrlProvider, but for the child-avatars bucket).
final signedChildAvatarUrlProvider = FutureProvider.family<String, String>((ref, path) {
  return ref.watch(childServiceProvider).getSignedChildAvatarUrl(path);
});
