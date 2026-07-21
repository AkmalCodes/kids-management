// One row per event (schedule_entries table) — not a JSON blob shared by a
// whole person's week. This lets each entry carry its own creator, which is
// what the edit/delete permission rule below depends on.
class ScheduleEntry {
  final String id;
  final String type; // 'child' | 'teacher'
  final String refId;
  final String centerId;
  final String day;
  final String startTime;
  final String endTime;
  final String label;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const ScheduleEntry({
    required this.id,
    required this.type,
    required this.refId,
    required this.centerId,
    required this.day,
    required this.startTime,
    required this.endTime,
    required this.label,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
  });

  factory ScheduleEntry.fromJson(Map<String, dynamic> json) => ScheduleEntry(
    id: json['id'] as String,
    type: json['type'] as String,
    refId: json['ref_id'] as String,
    centerId: json['center_id'] as String,
    day: json['day'] as String,
    startTime: json['start_time'] as String,
    endTime: json['end_time'] as String,
    label: json['label'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    createdBy: json['created_by'] as String?,
    updatedBy: json['updated_by'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'ref_id': refId,
    'center_id': centerId,
    'day': day,
    'start_time': startTime,
    'end_time': endTime,
    'label': label,
    'created_by': createdBy,
    'updated_by': updatedBy,
  };

  // Mirrors the schedule_entries_update/delete RLS policies: the creator or
  // any director can edit/delete; everyone else with view access is
  // read-only for this entry.
  bool canBeEditedBy({required String uid, required String role}) {
    return role == 'director' || createdBy == uid;
  }
}
