import 'package:flutter/material.dart';
import '../../core/models/schedule.dart';

// Used by both TeacherScheduleScreen and ParentScheduleScreen — the
// entries are stored flat in Postgres (JSONB array), grouped here purely
// for display so both screens don't duplicate the grouping logic.
class ScheduleList extends StatelessWidget {
  const ScheduleList({
    super.key,
    required this.entries,
    this.shrinkWrap = false,
    this.physics,
  });

  final List<ScheduleEntry> entries;

  // Set both when embedding this inside another scrollable (e.g. a parent
  // with multiple children, one ScheduleList per child) so it sizes to its
  // content instead of trying to scroll independently.
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  static const _dayOrder = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(child: Text('No schedule set yet.'));
    }

    final byDay = <String, List<ScheduleEntry>>{};
    for (final entry in entries) {
      byDay.putIfAbsent(entry.day, () => []).add(entry);
    }
    final days = byDay.keys.toList()
      ..sort((a, b) => _dayOrder.indexOf(a).compareTo(_dayOrder.indexOf(b)));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      shrinkWrap: shrinkWrap,
      physics: physics,
      itemCount: days.length,
      itemBuilder: (context, i) {
        final day = days[i];
        final dayEntries = byDay[day]!..sort((a, b) => a.startTime.compareTo(b.startTime));
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  day,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                for (final entry in dayEntries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Text(
                          '${entry.startTime} - ${entry.endTime}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(entry.label)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
