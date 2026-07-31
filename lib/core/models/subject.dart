// A center-defined lesson subject/category (e.g. Art, Numeracy). Directors
// manage the list; teachers tag lesson plans with one, and it surfaces on the
// schedule (a later increment). Kept deliberately small -- just a label + an
// optional display color.
class Subject {
  final String id;
  final String centerId;
  final String name;
  final String? color; // optional hex like '#RRGGBB', for chips
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const Subject({
    required this.id,
    required this.centerId,
    required this.name,
    this.color,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
  });

  factory Subject.fromJson(Map<String, dynamic> json) => Subject(
    id: json['id'] as String,
    centerId: json['center_id'] as String,
    name: json['name'] as String,
    color: json['color'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    createdBy: json['created_by'] as String?,
    updatedBy: json['updated_by'] as String?,
  );
}
