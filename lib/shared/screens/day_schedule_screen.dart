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
import '../widgets/day_timetable.dart';
import '../widgets/row_actions_sheet.dart';
import '../widgets/schedule_entry_form_dialog.dart';
import '../widgets/schedule_event_sheet.dart';
import '../widgets/week_strip.dart';

// The day timeline, screen design SA2 (Figma "Screen designs"). Pushed from
// ScheduleAgendaView ("Timeline", an event, or +).
//
//   < Wednesday, 21 Oct          [List]
//   M  T  W  T  F  S  S          <- same week strip as the agenda; picking a
//   07:00 ─────────────             day re-draws the grid without leaving
//   08:00 ▌Morning circle
//
// `entries` is the schedule's FULL list (every recurrence); this screen
// works out which fall on the shown day with scheduleEntryOccursOn, so it
// can switch days itself. It owns its own copy of that list so it can
// refresh after a create/update/delete without waiting on the parent.
//
// Tapping an event opens the SA3 details sheet (showScheduleEventSheet):
// Edit / Delete for its creator or a director, the attached lesson plan for
// everyone.
class DayScheduleScreen extends ConsumerStatefulWidget {
  const DayScheduleScreen({
    super.key,
    required this.date,
    required this.entries,
    this.type,
    this.refId,
    this.centerId,
    this.editable = false,
    this.addOnOpen = false,
    this.now,
  });

  // The day shown first.
  final DateTime date;
  final List<ScheduleEntry> entries;

  // Only required when editable is true — identifies whose schedule this
  // is, so new/changed entries are saved against the right row.
  final String? type;
  final String? refId;
  final String? centerId;
  final bool editable;

  // Open straight into the "Create Event" dialog: the agenda's + button
  // lands here, since creating an event (dialog, save, refresh) lives in
  // this screen.
  final bool addOnOpen;

  // Injectable "now" (date + time) for tests; null = DateTime.now().
  final DateTime? now;

  static const _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];
  static const _monthAbbrev = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  ConsumerState<DayScheduleScreen> createState() => _DayScheduleScreenState();
}

class _DayScheduleScreenState extends ConsumerState<DayScheduleScreen> {
  late DateTime _date;
  late List<ScheduleEntry> _all;
  String? _newEntryId;
  // For a class schedule (§6.5): the class's approved lesson plans, used to
  // (a) offer them in the event dialog's picker, (b) show the attached plan's
  // subject on an event, (c) open the plan from the event sheet.
  final Map<String, LessonPlan> _planById = {};
  final Map<String, String?> _subjectByPlanId = {}; // plan id -> subject name
  final Map<String, String> _titleByPlanId = {}; // plan id -> plan title
  List<LessonPlanOption> _planOptions = [];

  DateTime get _now => widget.now ?? DateTime.now();
  DateTime get _today => DateTime(_now.year, _now.month, _now.day);
  bool get _isToday =>
      _date.year == _today.year && _date.month == _today.month && _date.day == _today.day;

  @override
  void initState() {
    super.initState();
    _date = DateTime(widget.date.year, widget.date.month, widget.date.day);
    _all = widget.entries;
    if (widget.type == 'class' && widget.refId != null) {
      _loadPlans(widget.refId!);
    }
    if (widget.addOnOpen && widget.editable) {
      // After the first frame: a dialog needs this route to be on screen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _addEntry(DayTimetable.startHour);
      });
    }
  }

  List<ScheduleEntry> _entriesOn(DateTime date) =>
      _all.where((e) => scheduleEntryOccursOn(e, date)).toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

  Future<void> _loadPlans(String classId) async {
    final service = ref.read(lessonPlanControllerProvider);
    // Subject labels for every role via the connected-role RPC -- this is
    // what makes the subject show on events for parents (who can't read the
    // lesson_plans rows directly). Also drives the event dialog's picker.
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
      // Non-fatal: the schedule still works without subjects/the picker.
    }
    // Full plan rows (to open an attached plan's content, and to edit) --
    // readable by the teacher/director and, via widened RLS, connected
    // parents; empty otherwise. Non-fatal.
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

  // The subject to show on an event (null if it has no attached plan / the
  // plan has no subject).
  String? _subjectForEntry(ScheduleEntry entry) =>
      entry.lessonPlanId == null ? null : _subjectByPlanId[entry.lessonPlanId];

  String get _dayName => DayScheduleScreen._weekdayNames[_date.weekday - 1];

  // Marks ScheduleAgendaView's cached list stale so it re-fetches once the
  // user navigates back to it — cheap and non-blocking, unlike awaiting a
  // second round-trip here just to reflect a write we already know about.
  void _invalidateAgendaCache() {
    final type = widget.type;
    final refId = widget.refId;
    if (type == null || refId == null) return;
    ref.invalidate(scheduleEntriesProvider((type: type, refId: refId)));
  }

  Future<void> _addEntry(int hour) async {
    final user = await ref.read(currentUserProvider.future);
    final type = widget.type;
    final refId = widget.refId;
    final centerId = widget.centerId;
    if (!mounted) return;
    if (user == null || type == null || refId == null || centerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Can't add an event: your account has no center assigned. Contact your director.",
          ),
        ),
      );
      return;
    }

    final startTime = '${hour.toString().padLeft(2, '0')}:00';
    final endTime = '${(hour + 1).toString().padLeft(2, '0')}:00';

    final result = await showScheduleEntryFormDialog(
      context,
      anchorDate: _date,
      initialStartTime: startTime,
      initialEndTime: endTime,
      lessonPlans: _planOptions,
    );
    if (result is! ScheduleEntrySaved) return;

    final newEntry = await ref.read(scheduleControllerProvider).createEntry(
          type: type,
          refId: refId,
          centerId: centerId,
          day: _dayName,
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
      _all = [..._all, newEntry];
      _newEntryId = newEntry.id;
    });
    _invalidateAgendaCache();
  }

  // Opens the lesson plan attached to an event (read-only), if any.
  Future<void> _openPlan(ScheduleEntry entry) async {
    final id = entry.lessonPlanId;
    if (id == null) return;
    // Prefer the already-loaded plan; fall back to a fetch (e.g. it isn't in
    // the approved set we cached).
    final plan = _planById[id] ?? await ref.read(lessonPlanControllerProvider).getPlan(id);
    if (plan == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LessonPlanViewScreen(
          plan: plan,
          subjectName: _subjectByPlanId[id],
        ),
      ),
    );
  }

  Future<void> _tapEntry(ScheduleEntry entry) async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null || !mounted) return;

    final canEdit = widget.editable && entry.canBeEditedBy(uid: user.id, role: user.role);
    final planId = entry.lessonPlanId;
    final action = await showScheduleEventSheet(
      context,
      entry: entry,
      date: _date,
      subject: _subjectForEntry(entry),
      planTitle: planId == null ? null : (_planById[planId]?.title ?? _titleByPlanId[planId]),
      canEdit: canEdit,
      addedByYou: entry.createdBy == user.id,
      // Explain the missing buttons to someone who can edit this schedule in
      // general but not this particular event.
      readOnlyHint: widget.editable && !canEdit
          ? 'Only the creator or a director can edit this event.'
          : null,
    );
    if (action == null || !mounted) return;

    switch (action) {
      case ScheduleEventAction.openPlan:
        await _openPlan(entry);
      case ScheduleEventAction.delete:
        if (!await confirmDelete(context, message: 'Delete "${entry.label}"?')) return;
        await _deleteEntry(entry);
      case ScheduleEventAction.edit:
        await _editEntry(entry, user.id);
    }
  }

  Future<void> _deleteEntry(ScheduleEntry entry) async {
    await ref.read(scheduleControllerProvider).deleteEntry(entry.id);
    if (!mounted) return;
    setState(() {
      _all = _all.where((e) => e.id != entry.id).toList();
    });
    _invalidateAgendaCache();
  }

  Future<void> _editEntry(ScheduleEntry entry, String uid) async {
    final result = await showScheduleEntryFormDialog(
      context,
      anchorDate: entry.anchorDate ?? _date,
      existing: entry,
      lessonPlans: _planOptions,
    );
    if (result == null) return;

    switch (result) {
      case ScheduleEntrySaved(
          :final startTime,
          :final endTime,
          :final label,
          :final color,
          :final recurrence,
          :final anchorDate,
          :final lessonPlanId
        ):
        final updated = await ref.read(scheduleControllerProvider).updateEntry(
              id: entry.id,
              day: entry.day,
              startTime: startTime,
              endTime: endTime,
              label: label,
              color: color,
              recurrence: recurrence,
              anchorDate: anchorDate,
              lessonPlanId: lessonPlanId,
              actorUid: uid,
            );
        if (!mounted) return;
        setState(() {
          _all = [for (final e in _all) if (e.id == updated.id) updated else e];
        });
        _invalidateAgendaCache();
      // The edit dialog still has its own Delete button.
      case ScheduleEntryDeleted():
        await _deleteEntry(entry);
    }
  }

  void _selectDay(DateTime day) {
    setState(() {
      _date = day;
      _newEntryId = null; // don't replay the fade-in on another day
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = '${DayScheduleScreen._weekdayNames[_date.weekday - 1]}, '
        '${_date.day} ${DayScheduleScreen._monthAbbrev[_date.month - 1]}';
    final dayEntries = _entriesOn(_date);
    final now = _now;
    final nowTime = _isToday
        ? '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}'
        : null;

    // Read-only + empty has nothing to show. Editable stays on the grid
    // even when empty, so the very first event for the day can be added.
    final showEmptyMessage = !widget.editable && dayEntries.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          // Back to the agenda (the screen that pushed this one), labelled
          // as the other view rather than as "back".
          if (Navigator.of(context).canPop())
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.onAccent,
                  side: const BorderSide(color: AppTheme.hairline),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: const Size(0, 34),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                child: const Text('List'),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: WeekStrip(
              days: WeekStrip.weekOf(_date),
              selected: _date,
              today: _today,
              dotColorsFor: (d) =>
                  _entriesOn(d).map((e) => e.displayColor).toSet().take(3).toList(),
              onSelect: _selectDay,
              onSwipe: (dir) => _selectDay(DateTime(_date.year, _date.month, _date.day + 7 * dir)),
            ),
          ),
          Expanded(
            child: showEmptyMessage
                ? const Center(
                    child: Text('No activities on this day.',
                        style: TextStyle(color: AppTheme.mutedText)),
                  )
                : SingleChildScrollView(
                    // Bottom room so the last hours scroll clear of the FAB.
                    padding: EdgeInsets.only(bottom: widget.editable ? 72 : 0),
                    // onTapEntry is always wired: the event sheet shows
                    // details to everyone, with actions for those allowed.
                    child: DayTimetable(
                      entries: dayEntries,
                      onAddEntry: widget.editable ? _addEntry : null,
                      onTapEntry: _tapEntry,
                      subjectForEntry: _subjectForEntry,
                      newEntryId: _newEntryId,
                      nowTime: nowTime,
                    ),
                  ),
          ),
        ],
      ),
      // Tapping the empty grid also adds an event, but that gesture has no
      // visual hint — this button is the discoverable way to do it.
      floatingActionButton: widget.editable
          ? FloatingActionButton(
              onPressed: () => _addEntry(DayTimetable.startHour),
              tooltip: 'Add event',
              backgroundColor: AppTheme.onAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
