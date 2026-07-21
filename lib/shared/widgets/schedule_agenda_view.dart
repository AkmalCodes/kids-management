import 'package:flutter/material.dart';
import '../../core/models/schedule.dart';
import '../screens/day_schedule_screen.dart';

// Agenda-style schedule (modeled on typical calendar apps): date numbers
// down the left, colored event cards beside them, "No events" for empty
// days. A header button toggles between the current week and the whole
// month. Tapping a day pushes DayScheduleScreen with that day's timetable.
//
// Entries are a recurring weekly pattern (weekday + time, no calendar
// date), so each calendar date simply shows the entries whose `day`
// matches its weekday — the same class appears on every matching Monday.
class ScheduleAgendaView extends StatefulWidget {
  const ScheduleAgendaView({
    super.key,
    required this.entries,
    this.anchorDate,
    this.shrinkWrap = false,
    this.physics,
    this.type,
    this.refId,
    this.centerId,
    this.editable = false,
  });

  final List<ScheduleEntry> entries;

  // Injectable "today" so widget tests are date-deterministic; the real
  // screens leave it null and get DateTime.now().
  final DateTime? anchorDate;

  // Set shrinkWrap (and physics) when embedding inside another scrollable,
  // e.g. the parent screen that stacks one agenda per child.
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  // Forwarded into DayScheduleScreen so it can create/edit/delete entries.
  // Only required when editable is true.
  final String? type;
  final String? refId;
  final String? centerId;
  final bool editable;

  @override
  State<ScheduleAgendaView> createState() => _ScheduleAgendaViewState();
}

class _ScheduleAgendaViewState extends State<ScheduleAgendaView> {
  bool _monthView = false;

  static const _weekdayFull = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];
  static const _weekdayAbbrev = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _monthAbbrev = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  DateTime get _anchor => widget.anchorDate ?? DateTime.now();

  List<DateTime> get _visibleDates {
    final anchor = _anchor;
    if (_monthView) {
      // Day 0 of next month = last day of this month, so .day is the length.
      final daysInMonth = DateTime(anchor.year, anchor.month + 1, 0).day;
      return [
        for (int d = 1; d <= daysInMonth; d++) DateTime(anchor.year, anchor.month, d),
      ];
    }
    // DateTime.weekday: Monday = 1 … Sunday = 7.
    final monday = anchor.subtract(Duration(days: anchor.weekday - 1));
    return [
      for (int i = 0; i < 7; i++) DateTime(monday.year, monday.month, monday.day + i),
    ];
  }

  String get _headerLabel {
    if (_monthView) return '${_monthNames[_anchor.month - 1]} ${_anchor.year}';
    final dates = _visibleDates;
    final start = dates.first;
    final end = dates.last;
    final startLabel = '${_monthAbbrev[start.month - 1]} ${start.day}';
    return start.month == end.month
        ? '$startLabel – ${end.day}'
        : '$startLabel – ${_monthAbbrev[end.month - 1]} ${end.day}';
  }

  List<ScheduleEntry> _entriesFor(DateTime date) {
    final dayName = _weekdayFull[date.weekday - 1];
    return widget.entries.where((e) => e.day == dayName).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  void _openDay(DateTime date) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DayScheduleScreen(
          date: date,
          entries: _entriesFor(date),
          type: widget.type,
          refId: widget.refId,
          centerId: widget.centerId,
          editable: widget.editable,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // No early-return on empty entries: the grid itself (day rows, toggle)
    // should always render — an empty schedule just means every row falls
    // back to its own "No events" placeholder below.
    final dates = _visibleDates;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _headerLabel,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            tooltip: _monthView ? 'Week view' : 'Month view',
            icon: Icon(
              _monthView ? Icons.calendar_view_week : Icons.calendar_month,
            ),
            onPressed: () => setState(() => _monthView = !_monthView),
          ),
        ],
      ),
    );

    final list = ListView.builder(
      padding: const EdgeInsets.all(8),
      shrinkWrap: widget.shrinkWrap,
      physics: widget.physics ??
          (widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null),
      itemCount: dates.length,
      itemBuilder: (context, i) => _DayRow(
        date: dates[i],
        weekdayAbbrev: _weekdayAbbrev[dates[i].weekday - 1],
        entries: _entriesFor(dates[i]),
        onTap: () => _openDay(dates[i]),
      ),
    );

    if (widget.shrinkWrap) {
      return Column(mainAxisSize: MainAxisSize.min, children: [header, list]);
    }
    return Column(children: [header, Expanded(child: list)]);
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.date,
    required this.weekdayAbbrev,
    required this.entries,
    required this.onTap,
  });

  final DateTime date;
  final String weekdayAbbrev;
  final List<ScheduleEntry> entries;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 48,
              child: Column(
                children: [
                  Text(
                    '${date.day}',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(weekdayAbbrev, style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: entries.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'No events',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        for (final entry in entries)
                          Container(
                            key: Key('event-card-${entry.id}'),
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: entry.displayColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.label,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${entry.startTime} – ${entry.endTime}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
