class DailyReport {
  final String id;
  final String childId;
  final String teacherId;
  final String centerId;
  final String date; // YYYY-MM-DD
  final String text;
  final List<String> imageUrls;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const DailyReport({
    required this.id,
    required this.childId,
    required this.teacherId,
    required this.centerId,
    required this.date,
    required this.text,
    required this.imageUrls,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
  });

  factory DailyReport.fromJson(Map<String, dynamic> json) => DailyReport(
    id: json['id'] as String,
    childId: json['child_id'] as String,
    teacherId: json['teacher_id'] as String,
    centerId: json['center_id'] as String,
    date: json['date'] as String,
    text: json['text'] as String? ?? '',
    imageUrls: List<String>.from(json['image_urls'] as List),
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    createdBy: json['created_by'] as String?,
    updatedBy: json['updated_by'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'child_id': childId,
    'teacher_id': teacherId,
    'center_id': centerId,
    'date': date,
    'text': text,
    'image_urls': imageUrls,
    'created_by': createdBy,
    'updated_by': updatedBy,
  };
}
