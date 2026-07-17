import 'package:flutter/material.dart';
import '../../core/models/schedule.dart';

// Single-day timetable: hours down the left, entries drawn as blocks
// positioned by their start/end times — the detail view you land on when
// tapping a day in ScheduleAgendaView.
class DayTimetable extends StatelessWidget {
  const DayTimetable({super.key, required this.entries});

  final List<ScheduleEntry> entries;

  static const startHour = 7;
  static const endHour = 18;
  static const hourHeight = 56.0;
  static const _timeAxisWidth = 48.0;

  @override
  Widget build(BuildContext context) {
    final hourCount = endHour - startHour;
    final gridHeight = hourCount * hourHeight;
    final gridLineColor = Theme.of(context).dividerColor;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        height: gridHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _timeAxisWidth,
              height: gridHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (int h = startHour; h < endHour; h++)
                    Positioned(
                      top: (h - startHour) * hourHeight - 6,
                      child: Text(
                        '$h:00',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                height: gridHeight,
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: gridLineColor)),
                ),
                child: Stack(
                  children: [
                    for (int h = startHour; h < endHour; h++)
                      Positioned(
                        top: (h - startHour) * hourHeight,
                        left: 0,
                        right: 0,
                        child: Divider(height: 1, color: gridLineColor),
                      ),
                    for (final entry in entries) _EntryBlock(entry: entry),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryBlock extends StatelessWidget {
  const _EntryBlock({required this.entry});

  final ScheduleEntry entry;

  int _minutesSinceGridStart(String time) {
    final parts = time.split(':');
    return (int.parse(parts[0]) - DayTimetable.startHour) * 60 + int.parse(parts[1]);
  }

  @override
  Widget build(BuildContext context) {
    final startMinutes = _minutesSinceGridStart(entry.startTime);
    final endMinutes = _minutesSinceGridStart(entry.endTime);
    final top = (startMinutes / 60) * DayTimetable.hourHeight;
    final rawHeight = ((endMinutes - startMinutes) / 60) * DayTimetable.hourHeight;
    final height = rawHeight < 24 ? 24.0 : rawHeight;

    final colorScheme = Theme.of(context).colorScheme;

    return Positioned(
      top: top,
      left: 8,
      right: 8,
      height: height,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              entry.label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colorScheme.onPrimaryContainer,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // Hide the time line on very short blocks where it can't fit.
            if (height >= 40)
              Text(
                '${entry.startTime} – ${entry.endTime}',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
