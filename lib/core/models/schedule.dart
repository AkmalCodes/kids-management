class ScheduleEntry {
  final String day;
  final String startTime;
  final String endTime;
  final String label;

  const ScheduleEntry({
    required this.day,
    required this.startTime,
    required this.endTime,
    required this.label,
  });

  factory ScheduleEntry.fromJson(Map<String, dynamic> json) => ScheduleEntry(
    day: json['day'] as String,
    startTime: json['start_time'] as String,
    endTime: json['end_time'] as String,
    label: json['label'] as String,
  );

  Map<String, dynamic> toJson() => {
    'day': day,
    'start_time': startTime,
    'end_time': endTime,
    'label': label,
  };
}

class Schedule {
  final String id;
  final String type; // 'child' | 'teacher'
  final String refId;
  final String centerId;
  final List<ScheduleEntry> entries;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const Schedule({
    required this.id,
    required this.type,
    required this.refId,
    required this.centerId,
    required this.entries,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
  });

  factory Schedule.fromJson(Map<String, dynamic> json) => Schedule(
    id: json['id'] as String,
    type: json['type'] as String,
    refId: json['ref_id'] as String,
    centerId: json['center_id'] as String,
    entries: (json['entries'] as List)
        .map((e) => ScheduleEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    createdBy: json['created_by'] as String?,
    updatedBy: json['updated_by'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'ref_id': refId,
    'center_id': centerId,
    'entries': entries.map((e) => e.toJson()).toList(),
    'created_by': createdBy,
    'updated_by': updatedBy,
  };
}
