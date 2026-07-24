import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_service.dart';

// Account creation for anyone other than yourself always goes through the
// create-user Edge Function (see supabase/functions/create-user) -- it
// needs the service role key, which can never live in this app, so the
// privileged part happens server-side. This service just calls it and
// unpacks the error into something the UI can show directly.
class UserManagementService {
  final SupabaseClient _client;

  UserManagementService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // Invites a new teacher by email -- Supabase sends them a secure link to
  // set their own password; nothing is ever generated or transmitted here.
  Future<void> inviteTeacher({
    required String email,
    required String name,
    String phone = '',
  }) {
    return _invite({'role': 'teacher', 'email': email, 'name': name, 'phone': phone});
  }

  // Invites a new parent and links them to childId in one call.
  Future<void> inviteParent({
    required String email,
    required String name,
    required String childId,
    String phone = '',
  }) {
    return _invite({
      'role': 'parent',
      'email': email,
      'name': name,
      'phone': phone,
      'childId': childId,
    });
  }

  Future<void> _invite(Map<String, dynamic> body) async {
    try {
      await _client.functions.invoke('create-user', body: body);
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map && details['error'] is String
          ? details['error'] as String
          : e.reasonPhrase ?? 'Failed to create account';
      throw Exception(message);
    }
  }
}

final userManagementServiceProvider = Provider<UserManagementService>(
  (ref) => UserManagementService(client: ref.watch(supabaseClientProvider)),
);
