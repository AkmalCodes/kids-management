import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_service.dart';
import '../models/class_group.dart';

// Reads from the `classes` table. RLS lets directors see all, teachers see
// their own, and parents see the class their child is in.
class ClassService {
  final SupabaseClient _client;

  ClassService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // For the director's "assign a class" dropdown.
  Future<List<ClassGroup>> fetchAll() async {
    final rows = await _client.from('classes').select().order('name');
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
}

final classServiceProvider = Provider<ClassService>(
  (ref) => ClassService(client: ref.watch(supabaseClientProvider)),
);

// Resolves a single class by id (cached per id). Used to look up the
// class's teacher for the parent's schedule view.
final classGroupProvider = FutureProvider.family<ClassGroup?, String>((ref, id) {
  return ref.watch(classServiceProvider).getClass(id);
});
