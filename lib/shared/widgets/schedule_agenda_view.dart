import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/lesson_plan.dart';
import '../../core/models/schedule.dart';
import '../../core/controllers/lesson_plan_controller.dart';
import '../../core/controllers/schedule_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../features/shared_lessons/lesson_plan_view_screen.dart';
import '../util/schedule_recurrence.dart';
import '../util/schedule_time.dart';
import 'day_timetable.dart';
import 'schedule_event_sheet.dart';
import 'week_strip.dart';

// The whole Schedule tab in one screen, screen design SA (Figma page
// "Screen designs"), modelled on phone calendar apps:
//
//   October 2026            [Today] [calendar]
//   M  T  W  T  F  S  S      <- week strip; swipe for prev/next week,
//   19 20 21 22 23 24 25        dots = that day's event colours
//   Wednesday · 6 activities    [list|timeline]
//   08:00 | Morning circle            <- the selected day's agenda (SA1)
//   ...                                  or its hour grid (SA2)
//
// Tapping a day in the strip swaps what's below it. Tapping an event opens
// the event sheet (SA3: details, then Edit turns it into the form); + (or an
// empty hour in the timeline) opens the same sheet as a blank form. There is
// no separate day screen any more: it repeated this one in another layout.
// On today, finished events fade, the running one gets a "Now" chip and a
// pink line marks the current time.
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

  // Whose schedule this is, so created/changed entries are saved against
  // the right row. Only required when editable is true.
  final String? type;
  final String? refId;
  final String? centerId;
  final bool editable;

  @override
  ConsumerState<ScheduleAgendaView> createState() => _ScheduleAgendaViewState();
}

class _ScheduleAgendaViewState extends ConsumerState<ScheduleAgendaView> {
  // The day shown. The strip always shows its Mon–Sun week.
  late DateTime _selected;
  // false = agenda list (SA1), true = hour grid (SA2).
  bool _timeline = false;
  // Our own copy of the entries, so a create/edit/delete shows at once
  // instead of after the provider's re-fetch (which we also trigger, so other
  // screens catch up). Replaced whenever the parent passes a new list.
  late List<ScheduleEntry> _entries;
  String? _newEntryId; // fades in once on the timeline

  // For a class schedule (§6.5): the class's approved lesson plans, used to
  // (a) show the attached plan's subject on events, (b) offer plans in the
  // event form's picker, (c) open the plan from the event sheet. Subjects
  // and titles come via the connected-role RPC, so they resolve for parents.
  final Map<String, String?> _subjectByPlanId = {};
  final Map<String, String> _titleByPlanId = {};
  final Map<String, LessonPlan> _planById = {};
  List<LessonPlanOption> _planOptions = [];

  DateTime get _now => widget.anchorDate ?? DateTime.now();
  DateTime get _today => _dateOnly(_now);

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  void initState() {
    super.initState();
    _selected = _today;
    _entries = widget.entries;
    if (widget.type == 'class' && widget.refId != null) {
      _loadPlans(widget.refId!);
    }
  }

  @override
  void didUpdateWidget(covariant ScheduleAgendaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.entries, widget.entries)) _entries = widget.entries;
  }

  Future<void> _loadPlans(String classId) async {
    // ref.read inside the try: building the controller can itself fail
    // (e.g. no backend in widget tests), and plans are optional extras.
    final LessonPlanController service;
    try {
      service = ref.read(lessonPlanControllerProvider);
    } catch (_) {
      return;
    }
    try {
      final planSubjects = await service.fetchClassPlanSubjects(classId);
      if (!mounted) return;
      setState(() {
        _subjectByPlanId
          ..clear()
          ..addEntries(planSubjects.map((p) => MapEntry(p.id, p.subject)));
        _titleByPlanId
          ..clear()
          ..addEntries(planSubjects.map((p) => MapEntry(p.id, p.title)));
        _planOptions = [
          for (final p in planSubjects)
            (id: p.id, label: p.subject == null ? p.title : '${p.title} · ${p.subject}'),
        ];
      });
    } catch (_) {
      // Non-fatal: events just show no subject and the picker is hidden.
    }
    // Full plan rows (to open an attached plan's content) -- readable by the
    // teacher/director and, via widened RLS, connected parents. Non-fatal.
    try {
      final plans = await service.fetchApprovedForClass(classId);
      if (!mounted) return;
      setState(() {
        _planById
          ..clear()
          ..addEntries(plans.map((p) => MapEntry(p.id, p)));
      });
    } catch (_) {}
  }

  String? _subjectFor(ScheduleEntry entry) =>
      entry.lessonPlanId == null ? null : _subjectByPlanId[entry.lessonPlanId];

  static const _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

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
    return _entries.where((e) => scheduleEntryOccursOn(e, date)).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  // "HH:mm" for now, comparable with the entries' start/end strings.
  String get _nowHhmm =>
      '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';

  // Marks the provider's cached list stale so it re-fetches in the
  // background; our local copy already shows the change.
  void _invalidateCache() {
    final type = widget.type;
    final refId = widget.refId;
    if (type == null || refId == null) return;
    ref.invalidate(scheduleEntriesProvider((type: type, refId: refId)));
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // Create from + (hour = null: the next hour on today, else 08:00) or from
  // an empty hour tapped on the timeline.
  Future<void> _create({int? hour}) async {
    final user = await ref.read(currentUserProvider.future);
    final type = widget.type;
    final refId = widget.refId;
    final centerId = widget.centerId;
    if (!mounted) return;
    if (user == null || type == null || refId == null || centerId == null) {
      _showError("Can't add an event: your account has no center assigned. Contact your director.");
      return;
    }
    final startHour = hour ??
        (_sameDay(_selected, _today)
            ? (_now.hour + 1).clamp(DayTimetable.startHour, DayTimetable.endHour - 1)
            : 8);
    String hh(int h) => '${h.toString().padLeft(2, '0')}:00';

    final result = await showScheduleEventSheet(
      context,
      date: _selected,
      canEdit: true,
      lessonPlans: _planOptions,
      initialStartTime: hh(startHour),
      initialEndTime: hh(startHour + 1),
    );
    if (result is! ScheduleEntrySaved || !mounted) return;

    try {
      final created = await ref.read(scheduleControllerProvider).createEntry(
            type: type,
            refId: refId,
            centerId: centerId,
            day: _weekdayNames[_selected.weekday - 1],
            startTime: result.startTime,
            endTime: result.endTime,
            label: result.label,
            color: result.color,
            recurrence: result.recurrence,
            anchorDate: result.anchorDate,
            lessonPlanId: result.lessonPlanId,
            actorUid: user.id,
          );
      if (!mounted) return;
      setState(() {
        _entries = [..._entries, created];
        _newEntryId = created.id;
      });
      _invalidateCache();
    } catch (e) {
      if (mounted) _showError('Could not add the event: $e');
    }
  }

  // Tap on an event: the sheet's summary; Edit / Delete inside it for the
  // creator or a director; the plan card for everyone.
  Future<void> _openEntry(ScheduleEntry entry) async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null || !mounted) return;
    final canEdit = widget.editable && entry.canBeEditedBy(uid: user.id, role: user.role);
    final planId = entry.lessonPlanId;

    final result = await showScheduleEventSheet(
      context,
      entry: entry,
      date: _selected,
      subject: _subjectFor(entry),
      planTitle: planId == null ? null : (_planById[planId]?.title ?? _titleByPlanId[planId]),
      canEdit: canEdit,
      addedByYou: entry.createdBy == user.id,
      // Explain the missing buttons to someone who can edit this schedule in
      // general but not this particular event.
      readOnlyHint:
          widget.editable && !canEdit ? 'Only the creator or a director can edit this event.' : null,
      lessonPlans: _planOptions,
    );
    if (result == null || !mounted) return;

    if (result is ScheduleOpenPlan) {
      await _openPlan(entry);
      return;
    }
    // Only read the schedule controller for an actual write: read-only
    // viewers who just open a plan never need it.
    final service = ref.read(scheduleControllerProvider);
    try {
      switch (result) {
        case ScheduleOpenPlan():
          return; // handled above
        case ScheduleEntryDeleted():
          await service.deleteEntry(entry.id);
          if (!mounted) return;
          setState(() {
            _entries = _entries.where((e) => e.id != entry.id).toList();
          });
        case ScheduleEntrySaved():
          final updated = await service.updateEntry(
            id: entry.id,
            day: entry.day,
            startTime: result.startTime,
            endTime: result.endTime,
            label: result.label,
            color: result.color,
            recurrence: result.recurrence,
            anchorDate: result.anchorDate,
            lessonPlanId: result.lessonPlanId,
            actorUid: user.id,
          );
          if (!mounted) return;
          setState(() {
            _entries = [for (final e in _entries) if (e.id == updated.id) updated else e];
          });
      }
      _invalidateCache();
    } catch (e) {
      if (mounted) _showError('Could not save the change: $e');
    }
  }

  // Opens the lesson plan attached to an event (read-only).
  Future<void> _openPlan(ScheduleEntry entry) async {
    final id = entry.lessonPlanId;
    if (id == null) return;
    // Prefer the already-loaded plan; fall back to a fetch.
    final plan = _planById[id] ?? await ref.read(lessonPlanControllerProvider).getPlan(id);
    if (plan == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LessonPlanViewScreen(plan: plan, subjectName: _subjectByPlanId[id]),
      ),
    );
  }

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
      WeekStrip(
        days: WeekStrip.weekOf(_selected),
        selected: _selected,
        today: _today,
        dotColorsFor: (d) => _entriesFor(d).map((e) => e.displayColor).toSet().take(3).toList(),
        onSelect: (d) => setState(() {
          _selected = d;
          _newEntryId = null; // don't replay a fade-in on another day
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
          _ViewToggle(
            timeline: _timeline,
            onChanged: (v) => setState(() {
              _timeline = v;
            }),
          ),
        ],
      ),
      const SizedBox(height: 8),
    ];

    final body = <Widget>[];
    // Read-only + empty: nothing to draw either way. (Editable keeps the
    // grid when empty, so an hour can be tapped to add the first event.)
    if (dayEntries.isEmpty && !(_timeline && widget.editable)) {
      body.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('No activities on this day.',
              style: TextStyle(color: AppTheme.mutedText)),
        ),
      ));
    } else if (_timeline) {
      body.add(DayTimetable(
        entries: dayEntries,
        padding: const EdgeInsets.only(top: 8),
        onAddEntry: widget.editable ? (h) => _create(hour: h) : null,
        onTapEntry: _openEntry,
        subjectForEntry: _subjectFor,
        newEntryId: _newEntryId,
        nowTime: isToday ? now : null,
      ));
    } else {
      // Agenda rows, with the now line slotted in on today between the last
      // event that has started and the first that hasn't (only once at
      // least one event is behind us -- a line above everything says
      // nothing).
      final firstUpcoming = dayEntries.indexWhere((e) => e.startTime.compareTo(now) > 0);
      final nowLineAt = firstUpcoming == -1 ? dayEntries.length : firstUpcoming;
      for (var i = 0; i < dayEntries.length; i++) {
        if (isToday && i == nowLineAt && i > 0) body.add(_NowLine(time: now));
        final e = dayEntries[i];
        final done = isPast || (isToday && e.endTime.compareTo(now) <= 0);
        final running = isToday && !done && e.startTime.compareTo(now) <= 0;
        body.add(_AgendaRow(
          entry: e,
          subject: _subjectFor(e),
          done: done,
          running: running,
          onTap: () => _openEntry(e),
        ));
      }
      if (isToday && nowLineAt == dayEntries.length && dayEntries.isNotEmpty) {
        body.add(_NowLine(time: now));
      }
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
          children: [...header, ...body],
        ),
      );
    }

    final list = ListView(
      padding: padding,
      physics: widget.physics,
      children: [...header, ...body],
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
            onPressed: () => _create(),
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}

// List | Timeline switch: two icon segments in a pale track. Kept small
// because it's a preference, not something used every visit.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.timeline, required this.onChanged});

  final bool timeline;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget segment(bool isTimeline, IconData icon, String tooltip) {
      final on = timeline == isTimeline;
      return Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () => onChanged(isTimeline),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: on ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 18, color: on ? AppTheme.onAccent : AppTheme.mutedText),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.barTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          segment(false, Icons.view_agenda_outlined, 'List view'),
          segment(true, Icons.view_timeline_outlined, 'Timeline view'),
        ],
      ),
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

  @override
  Widget build(BuildContext context) {
    final color = entry.displayColor;
    // A darker shade of the event colour, readable on its own pale tint.
    final deep = Color.lerp(color, Colors.black, 0.3)!;
    final duration = scheduleDurationLabel(entry.startTime, entry.endTime);

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
