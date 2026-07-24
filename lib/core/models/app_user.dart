class AppUser {
  final String id;
  final String role;
  final String name;
  final String phone;
  final String? centerId;
  // Set true when a director invites this account; forces a set-password
  // screen on first entry, then cleared. Existing accounts default false.
  final bool mustSetPassword;
  // Storage path (private 'avatars' bucket) of the user's profile picture,
  // or null if they haven't set one. Not a ready URL -- exchange for a
  // signed URL to display (see ProfileService.getSignedAvatarUrl).
  final String? avatarPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const AppUser({
    required this.id,
    required this.role,
    required this.name,
    required this.phone,
    required this.centerId,
    this.mustSetPassword = false,
    this.avatarPath,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    role: json['role'] as String,
    name: json['name'] as String,
    phone: json['phone'] as String? ?? '',
    centerId: json['center_id'] as String?,
    mustSetPassword: json['must_set_password'] as bool? ?? false,
    avatarPath: json['avatar_path'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    createdBy: json['created_by'] as String?,
    updatedBy: json['updated_by'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'role': role,
    'name': name,
    'phone': phone,
    'center_id': centerId,
    'created_by': createdBy,
    'updated_by': updatedBy,
  };
}
