import 'package:flutter/material.dart';
import '../../core/models/schedule.dart';
import '../../core/theme/app_theme.dart';

// Single-day timetable: hours down the left, entries drawn as blocks
// positioned by their start/end times -- ScheduleAgendaView's "Timeline"
// view of the selected day.
//
// onAddEntry/onTapEntry are both optional — leave both null for a read-only
// view (e.g. a parent viewing their child's schedule). A single
// GestureDetector dispatches to whichever one applies based on tap
// position, rather than giving each entry block its own tap handler, so
// there's no ambiguity about which widget "wins" an overlapping tap.
//
// Look follows screen design SA2 (Figma "Screen designs"): hairline hour
// rows, events as pale washes of their colour with a solid bar down the
// left edge, and, when nowTime is given (viewing today), finished events
// fade and a pink line marks the current time.
class DayTimetable extends StatelessWidget {
  const DayTimetable({
    super.key,
    required this.entries,
    this.onAddEntry,
    this.onTapEntry,
    this.subjectForEntry,
    this.newEntryId,
    this.nowTime,
    this.padding = const EdgeInsets.all(16),
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

  // Current time as "HH:mm" when the day shown is today, else null. Drives
  // the now line and the fading of events that have ended.
  final String? nowTime;

  // Space around the grid. Taps are measured inside the grid itself, so
  // changing this never shifts which hour/entry a tap lands on.
  final EdgeInsetsGeometry padding;

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
    final tapEnabled = onAddEntry != null || onTapEntry != null;
    final now = nowTime;
    final nowMinutes = now == null ? null : minutesSinceGridStart(now);
    final showNowLine = nowMinutes != null && nowMinutes >= 0 && nowMinutes <= hourCount * 60;

    return Padding(
      padding: padding,
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
                      top: (h - startHour) * hourHeight - 7,
                      child: Text(
                        '${h.toString().padLeft(2, '0')}:00',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.mutedText,
                        ),
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
                child: SizedBox(
                  height: gridHeight,
                  child: Stack(
                    // The now line's dot pokes out to the left of the grid.
                    clipBehavior: Clip.none,
                    children: [
                      for (int h = startHour; h < endHour; h++)
                        Positioned(
                          top: (h - startHour) * hourHeight,
                          left: 0,
                          right: 0,
                          child: const Divider(height: 1, color: AppTheme.hairline),
                        ),
                      for (final entry in entries)
                        _EntryBlock(
                          entry: entry,
                          subject: subjectForEntry?.call(entry),
                          isNew: entry.id == newEntryId,
                          // String compare works: both are zero-padded HH:mm.
                          done: now != null && entry.endTime.compareTo(now) <= 0,
                        ),
                      if (showNowLine)
                        Positioned(
                          key: const Key('timetable-now-line'),
                          top: nowMinutes / 60 * hourHeight - 4.5,
                          left: -5,
                          right: 0,
                          child: IgnorePointer(
                            child: Row(
                              children: [
                                Container(
                                  width: 9,
                                  height: 9,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.accentPink,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Expanded(child: Container(height: 2, color: AppTheme.accentPink)),
                              ],
                            ),
                          ),
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
  const _EntryBlock({
    required this.entry,
    this.subject,
    this.isNew = false,
    this.done = false,
  });

  final ScheduleEntry entry;
  final String? subject;
  final bool isNew;
  final bool done; // already over today: drawn faded

  @override
  Widget build(BuildContext context) {
    final startMinutes = DayTimetable.minutesSinceGridStart(entry.startTime);
    final endMinutes = DayTimetable.minutesSinceGridStart(entry.endTime);
    final top = (startMinutes / 60) * DayTimetable.hourHeight;
    final rawHeight = ((endMinutes - startMinutes) / 60) * DayTimetable.hourHeight;
    final height = rawHeight < 24 ? 24.0 : rawHeight;

    final color = entry.displayColor;
    // Text in a deep shade of the event colour: readable on its own pale
    // wash, and it keeps each event visibly "its" colour.
    final deep = Color.lerp(color, Colors.black, 0.45)!;

    final block = Container(
      key: Key('entry-block-${entry.id}'),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: Key('entry-bar-${entry.id}'),
            width: 4,
            decoration: BoxDecoration(color: color),
          ),
          Expanded(
            child: Padding(
              // Short blocks (30 min = 26px) have no room for vertical
              // padding around their one centred line.
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: height >= 48 ? 4 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                // Short blocks centre their single line vertically.
                mainAxisAlignment:
                    height >= 48 ? MainAxisAlignment.start : MainAxisAlignment.center,
                children: [
                  Text(
                    entry.label,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: deep),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Room for the second (time) line: title ~20 + time ~16 plus
                  // 8px padding. At 40 a 45-min block (42px) overflowed by 2px.
                  if (height >= 48)
                    Row(
                      children: [
                        Text(
                          '${entry.startTime} – ${entry.endTime}',
                          style: TextStyle(fontSize: 11, color: deep),
                        ),
                        // The attached lesson plan's subject (own Text so it
                        // stays findable/ellipsised on its own).
                        if (subject != null) ...[
                          Text('  ·  ', style: TextStyle(fontSize: 11, color: deep)),
                          Icon(Icons.menu_book_outlined, size: 12, color: deep),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              subject!,
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w700, color: deep),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ),
          // Short block with a subject: show it on the right instead.
          if (height < 48 && subject != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: Text(
                    subject!,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: deep),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    final faded = Opacity(
      key: Key('entry-fade-${entry.id}'),
      opacity: done ? 0.5 : 1,
      child: block,
    );

    return Positioned(
      top: top + 1,
      left: 4,
      right: 0,
      height: height - 2,
      // Only the just-created block animates — a fixed Tween(0, 1) plays
      // once when this widget is first built and never restarts on later
      // rebuilds as long as the tween itself doesn't change.
      child: isNew
          ? TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 300),
              builder: (context, opacity, child) => Opacity(opacity: opacity, child: child),
              child: faded,
            )
          : faded,
    );
  }
}
