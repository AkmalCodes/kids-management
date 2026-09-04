// A class/group of children with zero or more assigned teachers (the
// `classes` table). Named ClassGroup because `Class` is a reserved word in
// Dart.
class ClassGroup {
  final String id;
  final String name;
  final List<String> teacherIds; // teacher_uids: every teacher on this class

  // Temporary bridge for call sites not yet moved to multi-select (removed
  // in the co-teachers plan's Task 5). Prefer teacherIds.
  String? get teacherId => teacherIds.isEmpty ? null : teacherIds.first;
  final String centerId;
  // Class photo in the private 'class-avatars' bucket, null if unset. Not a
  // ready URL — exchange for a signed URL to display (see
  // ClassController.getSignedClassAvatarUrl).
  final String? avatarPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const ClassGroup({
    required this.id,
    required this.name,
    required this.teacherIds,
    required this.centerId,
    this.avatarPath,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
  });

  factory ClassGroup.fromJson(Map<String, dynamic> json) => ClassGroup(
    id: json['id'] as String,
    name: json['name'] as String,
    teacherIds: (json['teacher_uids'] as List?)?.cast<String>() ?? const [],
    centerId: json['center_id'] as String,
    avatarPath: json['avatar_path'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    createdBy: json['created_by'] as String?,
    updatedBy: json['updated_by'] as String?,
  );
}
