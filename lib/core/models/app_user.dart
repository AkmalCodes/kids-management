class AppUser {
  final String id;
  final String role;
  final String name;
  final String phone;
  // Denormalized copy of the auth.users email so a director can display a
  // parent/teacher's email (auth.users itself isn't readable cross-user
  // from the client). Set by the create-user Edge Function; may be null on
  // accounts created before the column existed until backfilled.
  final String? email;
  // HR / contact details (all nullable — optional, editable by the user or a
  // director). address + emergency contact are plain text; dob is a date.
  final String? address;
  final DateTime? dob;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
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
    this.email,
    this.address,
    this.dob,
    this.emergencyContactName,
    this.emergencyContactPhone,
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
    email: json['email'] as String?,
    address: json['address'] as String?,
    dob: json['dob'] == null ? null : DateTime.parse(json['dob'] as String),
    emergencyContactName: json['emergency_contact_name'] as String?,
    emergencyContactPhone: json['emergency_contact_phone'] as String?,
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
