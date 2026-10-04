// One row of the generic `notifications` table (see design doc
// 2026-09-15-lesson-plan-notifications-design.md). Named AppNotification,
// not Notification -- Flutter's own framework already defines
// `Notification` (widgets/notifications.dart, used by
// NotificationListener<T extends Notification>); reusing the name would
// collide the moment this file and package:flutter/material.dart are both
// imported unqualified. Same reason AppUser isn't just User.
//
// read-only: the app never writes a full row (only the DB trigger does),
// so there is no toJson -- markRead patches just `read_at` directly.
class AppNotification {
  final String id;
  final String userId; // recipient
  final String type; // entity kind, e.g. 'lesson_plan'
  final String status; // event, e.g. 'SUBMITTED' | 'APPROVED' | 'REJECTED'
  final String title;
  final String body;
  final String entityId; // id of the row in the table named by `type`
  final DateTime? readAt; // null = unread
  final DateTime createdAt;
  final String? createdBy; // who caused it (submitter / reviewer)

  const AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.status,
    required this.title,
    required this.body,
    required this.entityId,
    this.readAt,
    required this.createdAt,
    this.createdBy,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        type: json['type'] as String,
        status: json['status'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        entityId: json['entity_id'] as String,
        readAt: json['read_at'] == null
            ? null
            : DateTime.parse(json['read_at'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        createdBy: json['created_by'] as String?,
      );
}
