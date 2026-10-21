import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/schedule.dart';
import '../../core/controllers/lesson_plan_controller.dart';
import '../../core/theme/app_theme.dart';
import '../screens/day_schedule_screen.dart';
import '../util/schedule_recurrence.dart';

// The Schedule tab's main view, screen design SA1 "Week strip + agenda"
// (Figma page "Screen designs"), modelled on phone calendar apps:
//
//   October 2026            [Today] [calendar]
//   M  T  W  T  F  S  S      <- week strip; swipe for prev/next week,
//   19 20 21 22 23 24 25        dots = that day's event colours
//   Wednesday · 6 activities     Timeline
//   08:00 | Morning circle            <- the selected day's agenda
//   ...
//
// Tapping a day in the strip swaps the agenda below it. "Timeline" (or
// tapping an event) pushes DayScheduleScreen, the hour-by-hour view where
// events are created/edited. On today's agenda, finished events fade, the
// running one gets a "Now" chip and a pink line marks the current time.
//
// Which entries fall on a date is decided by scheduleEntryOccursOn:
// - once: only on its anchor date
// - daily: Monday–Friday
// - weekly: the weekday matching `day` (e.g. 'Monday')
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

  // Injectable "now" (date AND time) so widget tests are deterministic; the
  // real screens leave it null and get DateTime.now().
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
  // The day whose agenda is shown. The strip always shows its Mon–Sun week.
  late DateTime _selected;
  // For a class schedule: plan id -> subject label, so the attached lesson's
  // subject shows on each event card. Loaded via the connected-role RPC so
  // it resolves for parents too.
  final Map<String, String?> _subjectByPlanId = {};

  DateTime get _now => widget.anchorDate ?? DateTime.now();
  DateTime get _today => _dateOnly(_now);

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  void initState() {
    super.initState();
    _selected = _today;
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

  static const _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];
  static const _weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  // Mon..Sun of the selected day's week. DateTime.weekday: Monday = 1.
  List<DateTime> get _week {
    final monday = _selected.subtract(Duration(days: _selected.weekday - 1));
    return [for (var i = 0; i < 7; i++) DateTime(monday.year, monday.month, monday.day + i)];
  }

  // Swipe: move a whole week, keeping the same weekday selected. Built with
  // the DateTime constructor (not Duration) so DST shifts can't skew it.
  void _shiftWeek(int direction) {
    setState(() {
      _selected = DateTime(_selected.year, _selected.month, _selected.day + 7 * direction);
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() {
        _selected = _dateOnly(picked);
      });
    }
  }

  List<ScheduleEntry> _entriesFor(DateTime date) {
    return widget.entries.where((e) => scheduleEntryOccursOn(e, date)).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  void _openDay(DateTime date, {bool addOnOpen = false}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DayScheduleScreen(
          date: date,
          entries: _entriesFor(date),
          type: widget.type,
          refId: widget.refId,
          centerId: widget.centerId,
          editable: widget.editable,
          addOnOpen: addOnOpen,
        ),
      ),
    );
  }

  // "HH:mm" for now, comparable with the entries' start/end strings.
  String get _nowHhmm =>
      '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final dayEntries = _entriesFor(_selected);
    final isToday = _sameDay(_selected, _today);
    final isPast = _selected.isBefore(_today);
    final now = _nowHhmm;

    final count = dayEntries.length;
    final countLabel = count == 0
        ? 'No activities'
        : '$count ${count == 1 ? 'activity' : 'activities'}';

    final header = <Widget>[
      _MonthHeader(
        label: '${_monthNames[_selected.month - 1]} ${_selected.year}',
        onToday: () => setState(() {
          _selected = _today;
        }),
        onPickDate: _pickDate,
      ),
      const SizedBox(height: 12),
      _WeekStrip(
        days: _week,
        selected: _selected,
        today: _today,
        letters: _weekdayLetters,
        dotColorsFor: (d) => _entriesFor(d).map((e) => e.displayColor).toSet().take(3).toList(),
        onSelect: (d) => setState(() {
          _selected = d;
        }),
        onSwipe: _shiftWeek,
      ),
      const SizedBox(height: 12),
      const Divider(height: 1, color: AppTheme.hairline),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: Text(
              '${_weekdayNames[_selected.weekday - 1]} · $countLabel',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.onAccent),
            ),
          ),
          TextButton(
            onPressed: () => _openDay(_selected),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.accentPink,
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Timeline'),
          ),
        ],
      ),
      const SizedBox(height: 4),
    ];

    // Agenda rows, with the now line slotted in on today's agenda between
    // the last event that has started and the first that hasn't (only once
    // at least one event is behind us -- a line above everything says
    // nothing).
    final rows = <Widget>[];
    if (dayEntries.isEmpty) {
      rows.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('No activities on this day.',
              style: TextStyle(color: AppTheme.mutedText)),
        ),
      ));
    }
    final firstUpcoming = dayEntries.indexWhere((e) => e.startTime.compareTo(now) > 0);
    final nowLineAt = firstUpcoming == -1 ? dayEntries.length : firstUpcoming;
    for (var i = 0; i < dayEntries.length; i++) {
      if (isToday && i == nowLineAt && i > 0) rows.add(_NowLine(time: now));
      final e = dayEntries[i];
      final done = isPast || (isToday && e.endTime.compareTo(now) <= 0);
      final running = isToday && !done && e.startTime.compareTo(now) <= 0;
      rows.add(_AgendaRow(
        entry: e,
        subject: _subjectFor(e),
        done: done,
        running: running,
        onTap: () => _openDay(_selected),
      ));
    }
    if (isToday && nowLineAt == dayEntries.length && dayEntries.isNotEmpty) {
      rows.add(_NowLine(time: now));
    }

    final showFab = widget.editable && !widget.shrinkWrap;
    // Extra bottom room so the last card can scroll clear of the FAB.
    final padding = EdgeInsets.fromLTRB(16, 16, 16, showFab ? 88 : 16);

    if (widget.shrinkWrap) {
      return Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [...header, ...rows],
        ),
      );
    }

    final list = ListView(
      padding: padding,
      physics: widget.physics,
      children: [...header, ...rows],
    );
    if (!showFab) return list;
    return Stack(
      children: [
        Positioned.fill(child: list),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            tooltip: 'Add event',
            backgroundColor: AppTheme.onAccent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            // Creating lives in the day view (dialog + save + refresh), so
            // open the selected day there with the create dialog up.
            onPressed: () => _openDay(_selected, addOnOpen: true),
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.label, required this.onToday, required this.onPickDate});

  final String label;
  final VoidCallback onToday;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.onAccent),
          ),
        ),
        OutlinedButton(
          onPressed: onToday,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.onAccent,
            side: const BorderSide(color: AppTheme.hairline),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            minimumSize: const Size(0, 34),
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          child: const Text('Today'),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Pick a date',
          onPressed: onPickDate,
          style: IconButton.styleFrom(
            backgroundColor: AppTheme.barTint,
            foregroundColor: AppTheme.onAccent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.calendar_month_outlined, size: 20),
        ),
      ],
    );
  }
}

// Seven equal cells, Mon..Sun. The selected day is a filled dark-rose tile;
// today (when not selected) gets its number in pink. A horizontal swipe
// anywhere on the strip moves a week.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.days,
    required this.selected,
    required this.today,
    required this.letters,
    required this.dotColorsFor,
    required this.onSelect,
    required this.onSwipe,
  });

  final List<DateTime> days;
  final DateTime selected;
  final DateTime today;
  final List<String> letters;
  final List<Color> Function(DateTime day) dotColorsFor;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<int> onSwipe;

  static String _key(DateTime d) =>
      'week-day-${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('week-strip'),
      // Fling left = later week, right = earlier. Velocity, not distance, so
      // a short quick swipe works and a slow drag doesn't trigger by accident.
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -200) onSwipe(1);
        if (v > 200) onSwipe(-1);
      },
      child: Row(
        children: [
          for (final d in days)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _DayCell(
                  key: Key(_key(d)),
                  letter: letters[d.weekday - 1],
                  day: d.day,
                  selected: d.year == selected.year &&
                      d.month == selected.month &&
                      d.day == selected.day,
                  isToday: d.year == today.year && d.month == today.month && d.day == today.day,
                  dots: dotColorsFor(d),
                  onTap: () => onSelect(d),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    super.key,
    required this.letter,
    required this.day,
    required this.selected,
    required this.isToday,
    required this.dots,
    required this.onTap,
  });

  final String letter;
  final int day;
  final bool selected;
  final bool isToday;
  final List<Color> dots;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppTheme.onAccent;
    return Material(
      color: selected ? AppTheme.onAccent : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Text(letter,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppTheme.mutedText,
                  )),
              const SizedBox(height: 2),
              Text('$day',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: (isToday && !selected) ? AppTheme.accentPink : fg,
                  )),
              const SizedBox(height: 4),
              // Fixed height so days with and without dots line up.
              SizedBox(
                height: 5,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final c in dots)
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(
                          color: selected ? Colors.white : c,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// One agenda line: start/end times on the left, then a white card with the
// event's colour as a bar down its left edge.
class _AgendaRow extends StatelessWidget {
  const _AgendaRow({
    required this.entry,
    required this.subject,
    required this.done,
    required this.running,
    required this.onTap,
  });

  final ScheduleEntry entry;
  final String? subject;
  final bool done; // already over: faded
  final bool running; // happening now: pink outline + "Now" chip
  final VoidCallback onTap;

  // "30 min", "1 hr", "1 hr 15 min" from the HH:mm strings.
  static String _duration(String start, String end) {
    int m(String s) => int.parse(s.substring(0, 2)) * 60 + int.parse(s.substring(3, 5));
    final total = m(end) - m(start);
    if (total <= 0) return '';
    final h = total ~/ 60, rest = total % 60;
    if (h == 0) return '$rest min';
    return rest == 0 ? '$h hr' : '$h hr $rest min';
  }

  @override
  Widget build(BuildContext context) {
    final color = entry.displayColor;
    // A darker shade of the event colour, readable on its own pale tint.
    final deep = Color.lerp(color, Colors.black, 0.3)!;
    final duration = _duration(entry.startTime, entry.endTime);

    return Opacity(
      key: Key('agenda-row-${entry.id}'),
      opacity: done ? 0.5 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 46,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.startTime,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.onAccent)),
                    Text(entry.endTime,
                        style: const TextStyle(fontSize: 11, color: AppTheme.mutedText)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Material(
                key: Key('event-card-${entry.id}'),
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: running ? AppTheme.accentPink : AppTheme.hairline,
                    width: running ? 1.5 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
                    // IntrinsicHeight lets the colour bar stretch to the
                    // card's height, whatever the title wraps to.
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            key: Key('event-bar-${entry.id}'),
                            width: 4,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.label,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.onAccent,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      if (duration.isNotEmpty)
                                        Text(duration,
                                            style: const TextStyle(
                                                fontSize: 12, color: AppTheme.mutedText)),
                                      if (subject != null)
                                        _Chip(
                                          background: color.withValues(alpha: 0.12),
                                          foreground: deep,
                                          icon: Icons.menu_book_outlined,
                                          label: subject!,
                                        ),
                                      if (running)
                                        const _Chip(
                                          background: AppTheme.accentPink,
                                          foreground: Colors.white,
                                          label: 'Now',
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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

class _Chip extends StatelessWidget {
  const _Chip({
    required this.background,
    required this.foreground,
    required this.label,
    this.icon,
  });

  final Color background;
  final Color foreground;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

// "10:12 ●──────" between the events that have started and those that
// haven't, on today's agenda only.
class _NowLine extends StatelessWidget {
  const _NowLine({required this.time});
  final String time;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('now-line'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(time,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.accentPink)),
          const SizedBox(width: 6),
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(color: AppTheme.accentPink, shape: BoxShape.circle),
          ),
          Expanded(child: Container(height: 2, color: AppTheme.accentPink)),
        ],
      ),
    );
  }
}
