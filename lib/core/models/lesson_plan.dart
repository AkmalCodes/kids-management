// The lifecycle of a lesson plan. Teachers move draft -> submitted; a
// director moves submitted -> approved/rejected. The DB (two UPDATE
// policies) is what actually stops a teacher self-approving; this enum just
// drives the UI.
enum LessonPlanStatus {
  draft,
  submitted,
  approved,
  rejected;

  static LessonPlanStatus fromDb(String value) => switch (value) {
        'submitted' => LessonPlanStatus.submitted,
        'approved' => LessonPlanStatus.approved,
        'rejected' => LessonPlanStatus.rejected,
        _ => LessonPlanStatus.draft,
      };

  String get db => name;
}

class LessonPlan {
  final String id;
  final String teacherId;
  final String centerId;
  final String title;
  final String content;
  final String? subjectId; // subjects.id (categorization), nullable
  final String? classId; // classes.id this plan is for, nullable
  final LessonPlanStatus status;
  final String? reviewedBy; // director who approved/rejected
  final DateTime? reviewedAt;
  final String? reviewNote; // director's note, e.g. reason for rejection
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const LessonPlan({
    required this.id,
    required this.teacherId,
    required this.centerId,
    required this.title,
    required this.content,
    this.subjectId,
    this.classId,
    this.status = LessonPlanStatus.draft,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewNote,
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
    content: json['content'] as String? ?? '',
    subjectId: json['subject_id'] as String?,
    classId: json['class_id'] as String?,
    status: LessonPlanStatus.fromDb(json['status'] as String? ?? 'draft'),
    reviewedBy: json['reviewed_by'] as String?,
    reviewedAt: json['reviewed_at'] == null
        ? null
        : DateTime.parse(json['reviewed_at'] as String),
    reviewNote: json['review_note'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    createdBy: json['created_by'] as String?,
    updatedBy: json['updated_by'] as String?,
  );
}
