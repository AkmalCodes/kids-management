class Child {
  final String id;
  final String name;
  final DateTime dob;
  final String centerId;
  final String className; // free-text class/group label (was "room")
  final String? teacherId;
  // The class (classes table) this child belongs to; its assigned teacher
  // drives what schedule the parent sees. Separate from teacherId, which
  // still drives attendance/report visibility.
  final String? classId;
  final String allergies;
  final String notes;
  // Storage path (private 'child-avatars' bucket) of the child's photo, or
  // null if unset. Exchange for a signed URL to display.
  final String? avatarPath;
  final DateTime enrolledAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const Child({
    required this.id,
    required this.name,
    required this.dob,
    required this.centerId,
    required this.className,
    required this.teacherId,
    this.classId,
    required this.allergies,
    required this.notes,
    this.avatarPath,
    required this.enrolledAt,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
  });

  factory Child.fromJson(Map<String, dynamic> json) => Child(
    id: json['id'] as String,
    name: json['name'] as String,
    dob: DateTime.parse(json['dob'] as String),
    centerId: json['center_id'] as String,
    className: json['class_name'] as String? ?? '',
    teacherId: json['teacher_id'] as String?,
    classId: json['class_id'] as String?,
    allergies: json['allergies'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
    avatarPath: json['avatar_path'] as String?,
    enrolledAt: DateTime.parse(json['enrolled_at'] as String),
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    createdBy: json['created_by'] as String?,
    updatedBy: json['updated_by'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'dob': dob.toIso8601String().substring(0, 10), // YYYY-MM-DD
    'center_id': centerId,
    'class_name': className,
    'teacher_id': teacherId,
    'class_id': classId,
    'allergies': allergies,
    'notes': notes,
    'avatar_path': avatarPath,
    'enrolled_at': enrolledAt.toIso8601String().substring(0, 10),
    'created_by': createdBy,
    'updated_by': updatedBy,
  };

  Child copyWith({
    String? name,
    DateTime? dob,
    String? className,
    String? teacherId,
    bool clearTeacherId = false,
    String? classId,
    bool clearClassId = false,
    String? allergies,
    String? notes,
    String? avatarPath,
    String? updatedBy,
  }) => Child(
    id: id,
    name: name ?? this.name,
    dob: dob ?? this.dob,
    centerId: centerId,
    className: className ?? this.className,
    teacherId: clearTeacherId ? null : (teacherId ?? this.teacherId),
    classId: clearClassId ? null : (classId ?? this.classId),
    allergies: allergies ?? this.allergies,
    notes: notes ?? this.notes,
    avatarPath: avatarPath ?? this.avatarPath,
    enrolledAt: enrolledAt,
    createdAt: createdAt,
    updatedAt: updatedAt,
    createdBy: createdBy,
    updatedBy: updatedBy ?? this.updatedBy,
  );
}
