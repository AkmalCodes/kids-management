import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/lesson_plan.dart';
import '../../core/models/schedule.dart';
import '../../core/controllers/lesson_plan_controller.dart';
import '../../core/controllers/schedule_controller.dart';
import '../../features/shared_lessons/lesson_plan_view_screen.dart';
import '../widgets/day_timetable.dart';
import '../widgets/schedule_entry_form_dialog.dart';

// Pushed by ScheduleAgendaView when a day row is tapped. `entries` is the
// already-filtered starting snapshot for that day; when `editable` is true
// this screen owns its own copy of that list so it can refresh itself
// after a create/update/delete without waiting on the parent to rebuild.
class DayScheduleScreen extends ConsumerStatefulWidget {
  const DayScheduleScreen({
    super.key,
    required this.date,
    required this.entries,
    this.type,
    this.refId,
    this.centerId,
    this.editable = false,
  });

  final DateTime date;
  final List<ScheduleEntry> entries;

  // Only required when editable is true — identifies whose schedule this
  // is, so new/changed entries are saved against the right row.
  final String? type;
  final String? refId;
  final String? centerId;
  final bool editable;

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
  late List<ScheduleEntry> _entries;
  String? _newEntryId;
  // For a class schedule (§6.5): the class's approved lesson plans, used to
  // (a) offer them in the event dialog's picker, (b) show the attached plan's
  // subject on an event, (c) open the plan when an event is tapped.
  final Map<String, LessonPlan> _planById = {};
  final Map<String, String?> _subjectByPlanId = {}; // plan id -> subject name
  List<LessonPlanOption> _planOptions = [];

  @override
  void initState() {
    super.initState();
    _entries = widget.entries;
    if (widget.type == 'class' && widget.refId != null) {
      _loadPlans(widget.refId!);
    }
  }

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

  String get _dayName => DayScheduleScreen._weekdayNames[widget.date.weekday - 1];

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
          // TODO(recurrence Task 5): use the dialog result
          recurrence: 'weekly',
          anchorDate: widget.date,
          lessonPlanId: result.lessonPlanId,
          actorUid: user.id,
        );
    if (!mounted) return;
    setState(() {
      _entries = [..._entries, newEntry]
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
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

    // Read-only viewers (or anyone who can't edit this event) instead open
    // the attached lesson plan, if there is one.
    final canEdit = widget.editable && entry.canBeEditedBy(uid: user.id, role: user.role);
    if (!canEdit) {
      if (entry.lessonPlanId != null) {
        await _openPlan(entry);
      } else if (widget.editable) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Only the creator or a director can edit this event.')),
        );
      }
      return;
    }

    final result = await showScheduleEntryFormDialog(
      context,
      existing: entry,
      lessonPlans: _planOptions,
    );
    if (result == null) return;

    final service = ref.read(scheduleControllerProvider);
    switch (result) {
      case ScheduleEntrySaved(
          :final startTime,
          :final endTime,
          :final label,
          :final color,
          :final lessonPlanId
        ):
        final updated = await service.updateEntry(
          id: entry.id,
          day: entry.day,
          startTime: startTime,
          endTime: endTime,
          label: label,
          color: color,
          // TODO(recurrence Task 5): use the dialog result
          recurrence: 'weekly',
          anchorDate: widget.date,
          lessonPlanId: lessonPlanId,
          actorUid: user.id,
        );
        if (!mounted) return;
        setState(() {
          _entries = [
            for (final e in _entries) if (e.id == updated.id) updated else e,
          ]..sort((a, b) => a.startTime.compareTo(b.startTime));
        });
      case ScheduleEntryDeleted():
        await service.deleteEntry(entry.id);
        if (!mounted) return;
        setState(() {
          _entries = _entries.where((e) => e.id != entry.id).toList();
        });
    }
    _invalidateAgendaCache();
  }

  @override
  Widget build(BuildContext context) {
    final title = '${DayScheduleScreen._weekdayNames[widget.date.weekday - 1]}, '
        '${DayScheduleScreen._monthAbbrev[widget.date.month - 1]} ${widget.date.day}';

    // Read-only + empty has nothing to show. Editable stays on the grid
    // even when empty, so the very first event for the day can be added.
    final showEmptyMessage = !widget.editable && _entries.isEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: showEmptyMessage
          ? const Center(child: Text('No events on this day.'))
          : SingleChildScrollView(
              // onTapEntry is always wired: an editable owner edits; everyone
              // else opens the event's attached lesson plan (if any).
              child: DayTimetable(
                entries: _entries,
                onAddEntry: widget.editable ? _addEntry : null,
                onTapEntry: _tapEntry,
                subjectForEntry: _subjectForEntry,
                newEntryId: _newEntryId,
              ),
            ),
      // Tapping the empty grid also adds an event, but that gesture has no
      // visual hint — this button is the discoverable way to do it.
      floatingActionButton: widget.editable
          ? FloatingActionButton(
              onPressed: () => _addEntry(DayTimetable.startHour),
              tooltip: 'Add event',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
