import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_service.dart';

// Profile pictures live in a private 'avatars' Storage bucket, one file per
// user keyed by their own id ('<uid>/avatar.jpg'), same private-bucket +
// signed-URL pattern as attendance photos.
class ProfileService {
  final SupabaseClient _client;

  ProfileService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // Deterministic path per user so replacing an avatar overwrites (upsert)
  // rather than piling up old files.
  Future<String> uploadAvatar({required String userId, required XFile photo}) async {
    final path = '$userId/avatar.jpg';
    final bytes = await photo.readAsBytes();
    await _client.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
    return path;
  }

  // Writes the path onto the caller's own profile via a SECURITY DEFINER
  // RPC -- avoids a broad profiles UPDATE policy that could let a user
  // change their own role. (Same reasoning as complete_password_setup.)
  Future<void> setAvatarPath(String path) => _client.rpc(
        'set_avatar_path',
        params: {'new_path': path},
      );

  Future<String> getSignedAvatarUrl(String path) =>
      _client.storage.from('avatars').createSignedUrl(path, 3600);
}

final profileServiceProvider = Provider<ProfileService>(
  (ref) => ProfileService(client: ref.watch(supabaseClientProvider)),
);

// Cached per path for the session so the avatar doesn't re-fetch a signed
// URL on every rebuild (same pattern as signedPhotoUrlProvider).
final signedAvatarUrlProvider = FutureProvider.family<String, String>((ref, path) {
  return ref.watch(profileServiceProvider).getSignedAvatarUrl(path);
});
