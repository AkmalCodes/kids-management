// A class/group of children with an assigned teacher (the `classes` table).
// Named ClassGroup because `Class` is a reserved word in Dart.
class ClassGroup {
  final String id;
  final String name;
  final String? teacherId; // teacher_uid: the teacher assigned to this class
  final String centerId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const ClassGroup({
    required this.id,
    required this.name,
    required this.teacherId,
    required this.centerId,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
  });

  factory ClassGroup.fromJson(Map<String, dynamic> json) => ClassGroup(
    id: json['id'] as String,
    name: json['name'] as String,
    teacherId: json['teacher_uid'] as String?,
    centerId: json['center_id'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    createdBy: json['created_by'] as String?,
    updatedBy: json['updated_by'] as String?,
  );
}
