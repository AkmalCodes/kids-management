class LessonPlan {
  final String id;
  final String teacherId;
  final String centerId;
  final String title;
  final String date; // YYYY-MM-DD
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const LessonPlan({
    required this.id,
    required this.teacherId,
    required this.centerId,
    required this.title,
    required this.date,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
  });

  factory LessonPlan.fromJson(Map<String, dynamic> json) => LessonPlan(
    id: json['id'] as String,
    teacherId: json['teacher_id'] as String,
    centerId: json['center_id'] as String,
    title: json['title'] as String,
    date: json['date'] as String,
    content: json['content'] as String? ?? '',
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    createdBy: json['created_by'] as String?,
    updatedBy: json['updated_by'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'teacher_id': teacherId,
    'center_id': centerId,
    'title': title,
    'date': date,
    'content': content,
    'created_by': createdBy,
    'updated_by': updatedBy,
  };
}
