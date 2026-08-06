import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';

class AuthController {
  final SupabaseClient _client;

  AuthController({SupabaseClient? client})
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

  // Emits true when a password-recovery deep link is opened (the app is now
  // authenticated with a recovery session and should force a new password),
  // false for every other auth event -- so completing the password update
  // (which fires userUpdated) naturally drops back out of recovery mode.
  Stream<bool> get passwordRecoveryStream => _client.auth.onAuthStateChange
      .map((event) => event.event == AuthChangeEvent.passwordRecovery);

  // The signed-in user's email lives on auth.users (not the profiles row),
  // so it's read straight off the current session rather than AppUser.
  String? get currentEmail => _client.auth.currentUser?.email;

  Future<void> signIn(String email, String password) =>
      _client.auth.signInWithPassword(email: email, password: password);

  Future<void> signOut() => _client.auth.signOut();

  // Sets the password for the *currently authenticated* user -- used both
  // after an invite (session already established via the invite deep link)
  // and after a password-recovery link. No old password needed: possession
  // of the valid session from the emailed link is the proof of identity.
  Future<void> updatePassword(String newPassword) =>
      _client.auth.updateUser(UserAttributes(password: newPassword));

  // Clears the must_set_password flag via a SECURITY DEFINER Postgres
  // function rather than a direct profiles UPDATE -- that keeps us from
  // having to grant users a broad update policy on their own profile row
  // (which could otherwise let them change their own role).
  Future<void> completePasswordSetup() => _client.rpc('complete_password_setup');

  // Sends a password-recovery email; the link deep-links back into the app
  // (see redirectTo scheme in AndroidManifest / Info.plist).
  Future<void> sendPasswordReset(String email) => _client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'com.example.test_flutter://login-callback/',
      );
}

final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final authControllerProvider = Provider<AuthController>(
  (ref) => AuthController(client: ref.watch(supabaseClientProvider)),
);

final currentUserProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authControllerProvider).userStream;
});

final passwordRecoveryProvider = StreamProvider<bool>((ref) {
  return ref.watch(authControllerProvider).passwordRecoveryStream;
});
