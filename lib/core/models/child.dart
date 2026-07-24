class Child {
  final String id;
  final String name;
  final DateTime dob;
  final String centerId;
  final String roomId;
  final String? teacherId;
  final String allergies;
  final String notes;
  final double? heightCm; // optional recorded height in centimetres
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
    this.heightCm,
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
    // Postgres numeric can come back as int or double, so coerce via num.
    heightCm: (json['height_cm'] as num?)?.toDouble(),
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
    'height_cm': heightCm,
    'enrolled_at': enrolledAt.toIso8601String().substring(0, 10),
    'created_by': createdBy,
    'updated_by': updatedBy,
  };

  Child copyWith({
    String? name,
    DateTime? dob,
    String? roomId,
    String? teacherId,
    bool clearTeacherId = false,
    String? allergies,
    String? notes,
    double? heightCm,
    bool clearHeight = false,
    String? updatedBy,
  }) => Child(
    id: id,
    name: name ?? this.name,
    dob: dob ?? this.dob,
    centerId: centerId,
    roomId: roomId ?? this.roomId,
    teacherId: clearTeacherId ? null : (teacherId ?? this.teacherId),
    allergies: allergies ?? this.allergies,
    notes: notes ?? this.notes,
    heightCm: clearHeight ? null : (heightCm ?? this.heightCm),
    enrolledAt: enrolledAt,
    createdAt: createdAt,
    updatedAt: updatedAt,
    createdBy: createdBy,
    updatedBy: updatedBy ?? this.updatedBy,
  );
}
