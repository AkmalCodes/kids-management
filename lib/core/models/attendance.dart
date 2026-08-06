enum AttendanceStatus { present, absent, late, excused }

class Attendance {
  final String id;
  final String childId;
  final String centerId;
  final String date; // YYYY-MM-DD
  final AttendanceStatus status;
  final String notes;
  // Both photos are entirely optional, independent of status and of each
  // other — teachers may attach either, neither, or both. Stored as
  // Supabase Storage object paths (private bucket), not ready-to-use
  // URLs: display code must exchange these for a signed URL (see
  // AttendanceController.getSignedPhotoUrl).
  final String? photoPath; // optional check-in photo
  final String? belongingsPhotoPath; // optional photo of the child's belongings/clothes
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const Attendance({
    required this.id,
    required this.childId,
    required this.centerId,
    required this.date,
    required this.status,
    required this.notes,
    required this.photoPath,
    required this.belongingsPhotoPath,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
  });

  factory Attendance.fromJson(Map<String, dynamic> json) => Attendance(
    id: json['id'] as String,
    childId: json['child_id'] as String,
    centerId: json['center_id'] as String,
    date: json['date'] as String,
    status: AttendanceStatus.values.firstWhere(
      (e) => e.name == (json['status'] as String),
    ),
    notes: json['notes'] as String? ?? '',
    photoPath: json['photo_path'] as String?,
    belongingsPhotoPath: json['belongings_photo_path'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    createdBy: json['created_by'] as String?,
    updatedBy: json['updated_by'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'child_id': childId,
    'center_id': centerId,
    'date': date,
    'status': status.name,
    'notes': notes,
    'photo_path': photoPath,
    'belongings_photo_path': belongingsPhotoPath,
    'created_by': createdBy,
    'updated_by': updatedBy,
  };
}
