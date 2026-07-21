import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_service.dart';
import '../../core/models/schedule.dart';
import '../../core/services/schedule_service.dart';
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

  @override
  void initState() {
    super.initState();
    _entries = widget.entries;
  }

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
    );
    if (result is! ScheduleEntrySaved) return;

    final newEntry = await ref.read(scheduleServiceProvider).createEntry(
          type: type,
          refId: refId,
          centerId: centerId,
          day: _dayName,
          startTime: result.startTime,
          endTime: result.endTime,
          label: result.label,
          color: result.color,
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

  Future<void> _tapEntry(ScheduleEntry entry) async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null || !mounted) return;

    if (!entry.canBeEditedBy(uid: user.id, role: user.role)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only the creator or a director can edit this event.')),
      );
      return;
    }

    final result = await showScheduleEntryFormDialog(context, existing: entry);
    if (result == null) return;

    final service = ref.read(scheduleServiceProvider);
    switch (result) {
      case ScheduleEntrySaved(:final startTime, :final endTime, :final label, :final color):
        final updated = await service.updateEntry(
          id: entry.id,
          day: entry.day,
          startTime: startTime,
          endTime: endTime,
          label: label,
          color: color,
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
              child: DayTimetable(
                entries: _entries,
                onAddEntry: widget.editable ? _addEntry : null,
                onTapEntry: widget.editable ? _tapEntry : null,
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
