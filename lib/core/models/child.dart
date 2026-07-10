class Child {
  final String id;
  final String name;
  final DateTime dob;
  final String centerId;
  final String roomId;
  final String? teacherId;
  final String allergies;
  final String notes;
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
    required this.roomId,
    required this.teacherId,
    required this.allergies,
    required this.notes,
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
    roomId: json['room_id'] as String? ?? '',
    teacherId: json['teacher_id'] as String?,
    allergies: json['allergies'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
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
    'room_id': roomId,
    'teacher_id': teacherId,
    'allergies': allergies,
    'notes': notes,
    'enrolled_at': enrolledAt.toIso8601String().substring(0, 10),
    'created_by': createdBy,
    'updated_by': updatedBy,
  };
}
