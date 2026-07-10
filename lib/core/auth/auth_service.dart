import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';

class AuthService {
  final SupabaseClient _client;

  AuthService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  Stream<AppUser?> get userStream =>
      _client.auth.onAuthStateChange.asyncMap((event) async {
        final session = event.session;
        if (session == null) return null;
        final data = await _client
            .from('profiles')
            .select()
            .eq('id', session.user.id)
            .single();
        return AppUser.fromJson(data);
      });

  Future<void> signIn(String email, String password) =>
      _client.auth.signInWithPassword(email: email, password: password);

  Future<void> signOut() => _client.auth.signOut();
}

final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(client: ref.watch(supabaseClientProvider)),
);

final currentUserProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authServiceProvider).userStream;
});
