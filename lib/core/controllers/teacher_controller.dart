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
}

final teacherControllerProvider = Provider<TeacherController>(
  (ref) => TeacherController(client: ref.watch(supabaseClientProvider)),
);
