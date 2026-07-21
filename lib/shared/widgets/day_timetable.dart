import 'package:flutter/material.dart';
import '../../core/models/schedule.dart';

// Single-day timetable: hours down the left, entries drawn as blocks
// positioned by their start/end times — the detail view you land on when
// tapping a day in ScheduleAgendaView.
//
// onAddEntry/onTapEntry are both optional — leave both null for a read-only
// view (e.g. a parent viewing their child's schedule). A single
// GestureDetector dispatches to whichever one applies based on tap
// position, rather than giving each entry block its own tap handler, so
// there's no ambiguity about which widget "wins" an overlapping tap.
class DayTimetable extends StatelessWidget {
  const DayTimetable({
    super.key,
    required this.entries,
    this.onAddEntry,
    this.onTapEntry,
  });

  final List<ScheduleEntry> entries;
  final void Function(int hour)? onAddEntry;
  final void Function(ScheduleEntry entry)? onTapEntry;

  static const startHour = 7;
  static const endHour = 18;
  static const hourHeight = 56.0;
  static const _timeAxisWidth = 48.0;

  static int minutesSinceGridStart(String time) {
    final parts = time.split(':');
    return (int.parse(parts[0]) - startHour) * 60 + int.parse(parts[1]);
  }

  void _handleTap(double localY) {
    final tappedMinutes = (localY / hourHeight * 60).round();
    for (final entry in entries) {
      final start = minutesSinceGridStart(entry.startTime);
      final end = minutesSinceGridStart(entry.endTime);
      if (tappedMinutes >= start && tappedMinutes < end) {
        onTapEntry?.call(entry);
        return;
      }
    }
    if (onAddEntry != null) {
      var hour = startHour + (localY / hourHeight).floor();
      if (hour < startHour) hour = startHour;
      if (hour > endHour - 1) hour = endHour - 1;
      onAddEntry!(hour);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hourCount = endHour - startHour;
    final gridHeight = hourCount * hourHeight;
    final gridLineColor = Theme.of(context).dividerColor;
    final tapEnabled = onAddEntry != null || onTapEntry != null;

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
              child: GestureDetector(
                key: const Key('day-timetable-grid'),
                behavior: HitTestBehavior.opaque,
                onTapUp: tapEnabled ? (details) => _handleTap(details.localPosition.dy) : null,
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

  @override
  Widget build(BuildContext context) {
    final startMinutes = DayTimetable.minutesSinceGridStart(entry.startTime);
    final endMinutes = DayTimetable.minutesSinceGridStart(entry.endTime);
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
