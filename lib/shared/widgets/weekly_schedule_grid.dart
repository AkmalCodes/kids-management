import 'package:flutter/material.dart';
import '../../core/models/schedule.dart';

// A recurring weekly timetable: days as columns, time-of-day as rows,
// entries drawn as positioned blocks — matches the shape of the underlying
// data (day-of-week + time, no calendar date) unlike a month/date grid.
class WeeklyScheduleGrid extends StatelessWidget {
  const WeeklyScheduleGrid({super.key, required this.entries});

  final List<ScheduleEntry> entries;

  static const _dayAbbrev = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _dayFullNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];
  static const _startHour = 7;
  static const _endHour = 18;
  static const _hourHeight = 48.0;
  static const _timeAxisWidth = 44.0;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(child: Text('No schedule set yet.'));
    }

    final entriesByDay = <String, List<ScheduleEntry>>{};
    for (final entry in entries) {
      entriesByDay.putIfAbsent(entry.day, () => []).add(entry);
    }

    final hourCount = _endHour - _startHour;
    final gridHeight = hourCount * _hourHeight;
    final gridLineColor = Theme.of(context).dividerColor;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: _timeAxisWidth),
              for (final abbrev in _dayAbbrev)
                Expanded(
                  child: Center(
                    child: Text(
                      abbrev,
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: gridHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _timeAxisWidth,
                  height: gridHeight,
                  child: Stack(
                    children: [
                      for (int h = _startHour; h < _endHour; h++)
                        Positioned(
                          top: (h - _startHour) * _hourHeight - 6,
                          child: Text(
                            '$h:00',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                    ],
                  ),
                ),
                for (final day in _dayFullNames)
                  Expanded(
                    child: Container(
                      height: gridHeight,
                      decoration: BoxDecoration(
                        border: Border(left: BorderSide(color: gridLineColor)),
                      ),
                      child: Stack(
                        children: [
                          for (int h = _startHour; h < _endHour; h++)
                            Positioned(
                              top: (h - _startHour) * _hourHeight,
                              left: 0,
                              right: 0,
                              child: Divider(height: 1, color: gridLineColor),
                            ),
                          for (final entry in entriesByDay[day] ?? [])
                            _EntryBlock(entry: entry),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryBlock extends StatelessWidget {
  const _EntryBlock({required this.entry});

  final ScheduleEntry entry;

  int _minutesSinceStart(String time) {
    final parts = time.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    return (hour - WeeklyScheduleGrid._startHour) * 60 + minute;
  }

  @override
  Widget build(BuildContext context) {
    final startMinutes = _minutesSinceStart(entry.startTime);
    final endMinutes = _minutesSinceStart(entry.endTime);
    final top = (startMinutes / 60) * WeeklyScheduleGrid._hourHeight;
    final rawHeight = ((endMinutes - startMinutes) / 60) * WeeklyScheduleGrid._hourHeight;
    final height = rawHeight < 20 ? 20.0 : rawHeight;

    final colorScheme = Theme.of(context).colorScheme;

    return Positioned(
      top: top,
      left: 2,
      right: 2,
      height: height,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.topLeft,
        child: Text(
          entry.label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colorScheme.onPrimaryContainer,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
