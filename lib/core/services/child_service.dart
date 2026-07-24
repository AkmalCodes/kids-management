import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_service.dart';
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
}

final childServiceProvider = Provider<ChildService>(
  (ref) => ChildService(client: ref.watch(supabaseClientProvider)),
);
