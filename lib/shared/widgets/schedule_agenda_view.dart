import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/schedule.dart';
import '../../core/controllers/lesson_plan_controller.dart';
import '../screens/day_schedule_screen.dart';
import '../util/schedule_recurrence.dart';

// Agenda-style schedule (modeled on typical calendar apps): date numbers
// down the left, colored event cards beside them, "No events" for empty
// days. A header button toggles between the current week and the whole
// month. Tapping a day pushes DayScheduleScreen with that day's timetable.
//
// Entries support four recurrence frequencies, determined by the `recurrence`
// field and interpreted by scheduleEntryOccursOn:
// - daily: shows on all weekdays (Monday–Friday)
// - weekly: shows on the weekday matching `day` (e.g., 'Monday')
// - monthly: shows on the day-of-month matching the anchor date, or the last
//   day of the month if the anchor day doesn't exist (e.g., 31st Jan anchor
//   shows on the last day of February)
// - annually: shows on the month+day matching the anchor date, with 29-Feb
//   anchors falling back to 28 Feb in non-leap years
// Each calendar date shows the entries whose recurrence rule matches it.
class ScheduleAgendaView extends ConsumerStatefulWidget {
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
  ConsumerState<ScheduleAgendaView> createState() => _ScheduleAgendaViewState();
}

class _ScheduleAgendaViewState extends ConsumerState<ScheduleAgendaView> {
  bool _monthView = false;
  // The period being shown. Starts at the injected/real "today" and the
  // prev/next arrows move it by a week (week view) or a month (month view).
  late DateTime _anchor;
  // For a class schedule: plan id -> subject label, so the attached lesson's
  // subject shows on each event card here too (not just the day view). Loaded
  // via the connected-role RPC so it resolves for parents.
  final Map<String, String?> _subjectByPlanId = {};

  @override
  void initState() {
    super.initState();
    _anchor = widget.anchorDate ?? DateTime.now();
    if (widget.type == 'class' && widget.refId != null) {
      _loadSubjects(widget.refId!);
    }
  }

  Future<void> _loadSubjects(String classId) async {
    try {
      final planSubjects =
          await ref.read(lessonPlanControllerProvider).fetchClassPlanSubjects(classId);
      if (!mounted) return;
      setState(() {
        _subjectByPlanId
          ..clear()
          ..addEntries(planSubjects.map((p) => MapEntry(p.id, p.subject)));
      });
    } catch (_) {
      // Non-fatal: cards just won't show a subject.
    }
  }

  String? _subjectFor(ScheduleEntry entry) =>
      entry.lessonPlanId == null ? null : _subjectByPlanId[entry.lessonPlanId];

  static const _weekdayAbbrev = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _monthAbbrev = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  // Move the shown period back/forward: a week in week view, a month in
  // month view. Month view pins to the 1st so month length never truncates.
  void _shift(int direction) {
    setState(() {
      if (_monthView) {
        _anchor = DateTime(_anchor.year, _anchor.month + direction, 1);
      } else {
        _anchor = _anchor.add(Duration(days: 7 * direction));
      }
    });
  }

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
    return widget.entries.where((e) => scheduleEntryOccursOn(e, date)).toList()
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
          IconButton(
            tooltip: _monthView ? 'Previous month' : 'Previous week',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _shift(-1),
          ),
          Expanded(
            child: Text(
              _headerLabel,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            tooltip: _monthView ? 'Next month' : 'Next week',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _shift(1),
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
      // Inset from the screen edges so the schedule doesn't touch the sides.
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shrinkWrap: widget.shrinkWrap,
      physics: widget.physics ??
          (widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null),
      itemCount: dates.length,
      itemBuilder: (context, i) => _DayRow(
        date: dates[i],
        weekdayAbbrev: _weekdayAbbrev[dates[i].weekday - 1],
        entries: _entriesFor(dates[i]),
        subjectForEntry: _subjectFor,
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
    this.subjectForEntry,
  });

  final DateTime date;
  final String weekdayAbbrev;
  final List<ScheduleEntry> entries;
  final VoidCallback onTap;
  final String? Function(ScheduleEntry entry)? subjectForEntry;

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
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Left: event title + time.
                                Expanded(
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
                                // Right: the attached lesson's subject.
                                if (subjectForEntry?.call(entry) != null) ...[
                                  Container(
                                    width: 1,
                                    height: 28,
                                    margin: const EdgeInsets.symmetric(horizontal: 8),
                                    color: Colors.white38,
                                  ),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 110),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.menu_book_outlined,
                                            size: 13, color: Colors.white70),
                                        const SizedBox(width: 3),
                                        Flexible(
                                          child: Text(
                                            subjectForEntry!.call(entry)!,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600),
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
