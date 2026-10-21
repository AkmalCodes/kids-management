import 'package:flutter/material.dart';
import '../../core/models/schedule.dart';
import '../../core/theme/app_theme.dart';
import '../util/schedule_time.dart';
import 'subject_tile.dart';

// What the person chose in the event sheet. The sheet only reports the
// choice; DayScheduleScreen does the work (edit dialog, delete, open plan),
// so the save/refresh logic stays in one place.
enum ScheduleEventAction { edit, delete, openPlan }

const _weekdayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];
const _monthAbbrev = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

// (headline, detail) for the repeat row, e.g. ("Every Wednesday", "Weekly").
(String, String) _repeatText(ScheduleEntry e, DateTime date) => switch (e.recurrence) {
      'daily' => ('Every weekday', 'Daily, Monday to Friday'),
      'once' => (
          'One time only',
          () {
            final d = e.anchorDate ?? date;
            return 'On ${d.day} ${_monthAbbrev[d.month - 1]} ${d.year}';
          }()
        ),
      _ => ('Every ${e.day}', 'Weekly'),
    };

// Event details bottom sheet, screen design SA3 (Figma "Screen designs"):
// colour dot + title, then time, repeat and creator rows, the attached
// lesson plan as a tappable card, and Delete / Edit for people allowed to
// change the event. Read-only viewers get the same sheet without buttons
// (plus `readOnlyHint`, when given, explaining why).
Future<ScheduleEventAction?> showScheduleEventSheet(
  BuildContext context, {
  required ScheduleEntry entry,
  required DateTime date,
  String? subject,
  String? planTitle,
  bool canEdit = false,
  bool addedByYou = false,
  String? readOnlyHint,
}) {
  return showModalBottomSheet<ScheduleEventAction>(
    context: context,
    isScrollControlled: true, // let it grow past half height when needed
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => _EventSheet(
      entry: entry,
      date: date,
      subject: subject,
      planTitle: planTitle,
      canEdit: canEdit,
      addedByYou: addedByYou,
      readOnlyHint: readOnlyHint,
    ),
  );
}

class _EventSheet extends StatelessWidget {
  const _EventSheet({
    required this.entry,
    required this.date,
    required this.subject,
    required this.planTitle,
    required this.canEdit,
    required this.addedByYou,
    required this.readOnlyHint,
  });

  final ScheduleEntry entry;
  final DateTime date;
  final String? subject;
  final String? planTitle;
  final bool canEdit;
  final bool addedByYou;
  final String? readOnlyHint;

  @override
  Widget build(BuildContext context) {
    final duration = scheduleDurationLabel(entry.startTime, entry.endTime);
    final dateLabel = '${_weekdayNames[date.weekday - 1]}, ${date.day} ${_monthAbbrev[date.month - 1]}';
    final (repeatHead, repeatDetail) = _repeatText(entry, date);
    void pop(ScheduleEventAction a) => Navigator.of(context).pop(a);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Grabber: the visual cue that the sheet can be dragged away.
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.fieldBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: entry.displayColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.label,
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w800, color: AppTheme.onAccent),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  color: AppTheme.mutedText,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.schedule,
              title: '${entry.startTime} – ${entry.endTime}',
              detail: duration.isEmpty ? dateLabel : '$dateLabel · $duration',
            ),
            _InfoRow(icon: Icons.repeat, title: repeatHead, detail: repeatDetail),
            if (addedByYou) const _InfoRow(icon: Icons.person_outline, title: 'Added by you'),
            if (entry.lessonPlanId != null) ...[
              const SizedBox(height: 6),
              const Text(
                'LESSON PLAN',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                  color: AppTheme.mutedText,
                ),
              ),
              const SizedBox(height: 8),
              Material(
                key: const Key('event-sheet-plan'),
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: AppTheme.hairline),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => pop(ScheduleEventAction.openPlan),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        SubjectTile(name: subject, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                planTitle ?? 'Lesson plan',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.onAccent,
                                ),
                              ),
                              Text(
                                subject == null
                                    ? 'Approved lesson plan'
                                    : '$subject · Approved lesson plan',
                                style: const TextStyle(fontSize: 12, color: AppTheme.mutedText),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: AppTheme.mutedText),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            if (canEdit)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => pop(ScheduleEventAction.delete),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFB3261E),
                        side: const BorderSide(color: Color(0xFFB3261E), width: 1.5),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => pop(ScheduleEventAction.edit),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.onAccent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit'),
                    ),
                  ),
                ],
              )
            else if (readOnlyHint != null)
              Text(
                readOnlyHint!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppTheme.mutedText),
              ),
          ],
        ),
      ),
    );
  }
}

// Icon tile + a bold line + an optional muted detail line.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.title, this.detail});

  final IconData icon;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.barTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppTheme.onAccent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.onAccent)),
                if (detail != null)
                  Text(detail!, style: const TextStyle(fontSize: 12, color: AppTheme.mutedText)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
