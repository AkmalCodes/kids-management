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
    this.subjectForEntry,
    this.newEntryId,
  });

  final List<ScheduleEntry> entries;
  final void Function(int hour)? onAddEntry;
  final void Function(ScheduleEntry entry)? onTapEntry;

  // Resolves the subject label to show on an event (from its attached lesson
  // plan), or null. Optional so non-class schedules pass nothing.
  final String? Function(ScheduleEntry entry)? subjectForEntry;

  // If set, only the block whose id matches fades in — every other block
  // renders immediately, so editing/deleting an entry doesn't cause the
  // whole day to re-fade.
  final String? newEntryId;

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
                      for (final entry in entries)
                        _EntryBlock(
                          entry: entry,
                          subject: subjectForEntry?.call(entry),
                          isNew: entry.id == newEntryId,
                        ),
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
  const _EntryBlock({required this.entry, this.subject, this.isNew = false});

  final ScheduleEntry entry;
  final String? subject;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final startMinutes = DayTimetable.minutesSinceGridStart(entry.startTime);
    final endMinutes = DayTimetable.minutesSinceGridStart(entry.endTime);
    final top = (startMinutes / 60) * DayTimetable.hourHeight;
    final rawHeight = ((endMinutes - startMinutes) / 60) * DayTimetable.hourHeight;
    final height = rawHeight < 24 ? 24.0 : rawHeight;

    // The palette (schedule_colors.dart) is all fairly saturated/dark
    // swatches, so white text reads reliably on every one of them —
    // matching the agenda view's cards, which use the same assumption.
    final block = Container(
      key: Key('entry-block-${entry.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: entry.displayColor,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: event title + time.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.label,
                  style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // Room for the second (time) line: title ~20 + time ~16 plus
                // 8px padding. At 40 a 45-min block (42px) overflowed by 2px.
                if (height >= 48)
                  Text(
                    '${entry.startTime} – ${entry.endTime}',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
              ],
            ),
          ),
          // Right: the attached lesson plan's subject, split off by a faint
          // divider so the block reads as two halves.
          if (subject != null) ...[
            Container(
              width: 1,
              height: height - 12,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: Colors.white38,
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.menu_book_outlined, size: 13, color: Colors.white70),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      subject!,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    return Positioned(
      top: top,
      left: 8,
      right: 8,
      height: height,
      // Only the just-created block animates — a fixed Tween(0, 1) plays
      // once when this widget is first built and never restarts on later
      // rebuilds as long as the tween itself doesn't change.
      child: isNew
          ? TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 300),
              builder: (context, opacity, child) => Opacity(opacity: opacity, child: child),
              child: block,
            )
          : block,
    );
  }
}
