import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_controller.dart';
import '../models/app_user.dart';

// Profile pictures live in a private 'avatars' Storage bucket, one file per
// user keyed by their own id ('<uid>/avatar.jpg'), same private-bucket +
// signed-URL pattern as attendance photos.
class ProfileController {
  final SupabaseClient _client;

  ProfileController({SupabaseClient? client})
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

  // Director-only: sets the avatar path on ANOTHER user's profile, via the
  // profiles_update_director policy. Used when a director changes a
  // teacher's/parent's photo. (Self uses setAvatarPath's RPC instead.)
  Future<void> setAvatarPathFor({
    required String userId,
    required String path,
    required String actorUid,
  }) async {
    await _client.from('profiles').update({
      'avatar_path': path,
      'updated_by': actorUid,
    }).eq('id', userId);
  }

  Future<String> getSignedAvatarUrl(String path) =>
      _client.storage.from('avatars').createSignedUrl(path, 3600);

  // Director-only edit of another user's profile (name/phone + HR fields),
  // per the profiles_update_director RLS policy. A regular user can't use
  // this -- the policy checks the caller is a director. `dob` is an ISO date
  // (yyyy-MM-dd) or null. Returns the saved row.
  Future<AppUser> updatePersonDetails({
    required String userId,
    required String name,
    required String phone,
    String? address,
    String? dob,
    String? emergencyContactName,
    String? emergencyContactPhone,
    required String actorUid,
  }) async {
    final row = await _client.from('profiles').update({
      'name': name,
      'phone': phone,
      'address': address,
      'dob': dob,
      'emergency_contact_name': emergencyContactName,
      'emergency_contact_phone': emergencyContactPhone,
      'updated_by': actorUid,
    }).eq('id', userId).select().single();
    return AppUser.fromJson(row);
  }

  // Any user editing their OWN name/phone + HR fields, via a SECURITY
  // DEFINER RPC that only ever touches auth.uid()'s row and only these
  // columns -- so it can't be used to change one's own role (same reasoning
  // as set_avatar_path). `dob` is an ISO date (yyyy-MM-dd) or null. Returns
  // the updated profile.
  Future<AppUser> updateOwnDetails({
    required String name,
    required String phone,
    String? address,
    String? dob,
    String? emergencyContactName,
    String? emergencyContactPhone,
  }) async {
    final row = await _client.rpc(
      'update_own_profile',
      params: {
        'new_name': name,
        'new_phone': phone,
        'new_address': address,
        'new_dob': dob,
        'new_emergency_contact_name': emergencyContactName,
        'new_emergency_contact_phone': emergencyContactPhone,
      },
    );
    return AppUser.fromJson(row as Map<String, dynamic>);
  }
}

final profileControllerProvider = Provider<ProfileController>(
  (ref) => ProfileController(client: ref.watch(supabaseClientProvider)),
);

// Cached per path for the session so the avatar doesn't re-fetch a signed
// URL on every rebuild (same pattern as signedPhotoUrlProvider).
final signedAvatarUrlProvider = FutureProvider.family<String, String>((ref, path) {
  return ref.watch(profileControllerProvider).getSignedAvatarUrl(path);
});
