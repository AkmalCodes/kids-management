import 'package:flutter/material.dart';
import '../constants/schedule_colors.dart';

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
  final String color; // bare 6-digit hex, e.g. '26A69A' — see displayColor
  // Optional approved lesson plan attached to this event (§6.5). Its subject
  // shows on the event; tapping opens the plan. null = no plan attached.
  final String? lessonPlanId;
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
    required this.color,
    this.lessonPlanId,
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
    color: json['color'] as String? ?? defaultScheduleColorHex,
    lessonPlanId: json['lesson_plan_id'] as String?,
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
    'color': color,
    'lesson_plan_id': lessonPlanId,
    'created_by': createdBy,
    'updated_by': updatedBy,
  };

  Color get displayColor => colorFromScheduleHex(color);

  // Mirrors the schedule_entries_update/delete RLS policies: the creator or
  // any director can edit/delete; everyone else with view access is
  // read-only for this entry.
  bool canBeEditedBy({required String uid, required String role}) {
    return role == 'director' || createdBy == uid;
  }
}
