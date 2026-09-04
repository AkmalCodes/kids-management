import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_controller.dart';
import '../models/app_user.dart';

class TeacherController {
  final SupabaseClient _client;

  TeacherController({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // Relies on the profiles_select RLS policy (director sees all profiles)
  // rather than filtering by center here — fine at this app's scale.
  Future<List<AppUser>> fetchAll() async {
    final rows = await _client
        .from('profiles')
        .select()
        .eq('role', 'teacher')
        .order('name');
    return (rows as List)
        .map((row) => AppUser.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  // Teachers who share at least one class with `myUid` (co-teachers),
  // excluding the caller. Two queries, like ChildController.fetchParentsForChild:
  // first the caller's classes (RLS already limits `classes` to ones they are
  // on), then the profiles for the union of those classes' teacher_uids.
  // Relies on the co-teacher branch of profiles_select for the second query.
  Future<List<AppUser>> fetchCoTeachers(String myUid) async {
    final classRows = await _client
        .from('classes')
        .select('teacher_uids')
        .contains('teacher_uids', [myUid]);
    final ids = <String>{
      for (final row in classRows as List)
        ...((row['teacher_uids'] as List).cast<String>()),
    }..remove(myUid);
    if (ids.isEmpty) return [];
    final rows = await _client
        .from('profiles')
        .select()
        .inFilter('id', ids.toList())
        .order('name');
    return (rows as List)
        .map((row) => AppUser.fromJson(row as Map<String, dynamic>))
        .toList();
  }
}

final teacherControllerProvider = Provider<TeacherController>(
  (ref) => TeacherController(client: ref.watch(supabaseClientProvider)),
);
