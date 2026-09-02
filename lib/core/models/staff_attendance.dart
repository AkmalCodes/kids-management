import 'attendance.dart' show AttendanceStatus;

// A teacher's attendance for one day. Deliberately a separate table/model
// from Attendance (children) rather than a nullable child_id/staff_id on one
// shared table -- see docs/superpowers/specs/2026-09-02-staff-attendance-schema-design.md
// for why. No photo fields: the safety/handoff reasoning for child photos
// does not apply to staff.
class StaffAttendance {
  final String id;
  final String staffId;
  final String centerId;
  final String date; // YYYY-MM-DD
  final AttendanceStatus status;
  final String notes;
  // Real wall-clock times the teacher started/finished work, set by the
  // clock-in/out flow. Distinct from createdAt/updatedAt (row audit): a
  // future correction would touch updatedAt without changing when the person
  // actually clocked in. See
  // docs/superpowers/specs/2026-09-02-staff-clock-in-out-design.md.
  // Stored as TIMESTAMPTZ; parsed here as UTC, call .toLocal() to display.
  final DateTime? clockInAt;
  final DateTime? clockOutAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const StaffAttendance({
    required this.id,
    required this.staffId,
    required this.centerId,
    required this.date,
    required this.status,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
    this.clockInAt,
    this.clockOutAt,
  });

  factory StaffAttendance.fromJson(Map<String, dynamic> json) => StaffAttendance(
    id: json['id'] as String,
    staffId: json['staff_id'] as String,
    centerId: json['center_id'] as String,
    date: json['date'] as String,
    status: AttendanceStatus.values.firstWhere(
      (e) => e.name == (json['status'] as String),
    ),
    notes: json['notes'] as String? ?? '',
    clockInAt: json['clock_in_at'] == null
        ? null
        : DateTime.parse(json['clock_in_at'] as String),
    clockOutAt: json['clock_out_at'] == null
        ? null
        : DateTime.parse(json['clock_out_at'] as String),
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    createdBy: json['created_by'] as String?,
    updatedBy: json['updated_by'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'staff_id': staffId,
    'center_id': centerId,
    'date': date,
    'status': status.name,
    'notes': notes,
    'created_by': createdBy,
    'updated_by': updatedBy,
  };
}
