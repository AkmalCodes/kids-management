import 'package:flutter/material.dart';
import '../../core/constants/schedule_colors.dart';
import '../../core/models/schedule.dart';
import '../../core/theme/app_theme.dart';
import '../util/schedule_time.dart';
import 'app_dropdown_field.dart';
import 'row_actions_sheet.dart';
import 'subject_tile.dart';

// The one place a schedule event is viewed, edited and created (screen
// design SA3, Figma "Screen designs"). It replaced the old AlertDialog form.
//
// - View mode (tap an event): a summary -- time, repeat rule, the attached
//   lesson plan as a card -- plus Delete / Edit for people allowed to change
//   the event.
// - Edit mode (tap Edit): the SAME sheet swaps the summary for inputs;
//   Cancel goes back to the summary instead of closing.
// - Create mode (entry == null, from + or an empty timeline hour): opens
//   straight into the inputs; Cancel closes.
//
// The sheet only reports what was chosen (a ScheduleSheetResult); the
// caller does the saving, so the database/refresh logic lives in one place.

sealed class ScheduleSheetResult {}

class ScheduleEntrySaved extends ScheduleSheetResult {
  ScheduleEntrySaved({
    required this.startTime,
    required this.endTime,
    required this.label,
    required this.color,
    required this.recurrence,
    required this.anchorDate,
    this.lessonPlanId,
  });
  final String startTime;
  final String endTime;
  final String label;
  final String color;
  // One of 'once' / 'daily' / 'weekly'.
  final String recurrence;
  // The calendar date the recurrence rule is measured from: the entry's own
  // anchor when editing (so a one-off keeps its date), else the day viewed.
  final DateTime anchorDate;
  // The approved lesson plan attached to this event, or null for none.
  final String? lessonPlanId;
}

// Delete was chosen AND confirmed inside the sheet.
class ScheduleEntryDeleted extends ScheduleSheetResult {}

// The attached lesson plan's card was tapped.
class ScheduleOpenPlan extends ScheduleSheetResult {}

// One attachable lesson plan, pre-labelled by the caller (title · subject) so
// this sheet stays decoupled from the subjects list.
typedef LessonPlanOption = ({String id, String label});

const _weekdayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];
const _monthAbbrev = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

// The concrete rule under the Repeats picker. For weekly it prefers the
// entry's own day (when editing) over the anchor's weekday.
String _recurrenceHelp(String recurrence, DateTime anchor, {String? day}) => switch (recurrence) {
      'once' => 'Occurs once on ${anchor.day} ${_monthAbbrev[anchor.month - 1]} ${anchor.year}',
      'daily' => 'Repeats every weekday',
      _ => 'Repeats every ${day ?? _weekdayNames[anchor.weekday - 1]}',
    };

// (headline, detail) for the summary's repeat row.
(String, String) _repeatSummary(ScheduleEntry e, DateTime date) => switch (e.recurrence) {
      'daily' => ('Every weekday', 'Daily, Monday to Friday'),
      'once' => (
          'One time only',
          () {
            final d = e.anchorDate ?? date;
            return 'On ${d.day} ${_monthAbbrev[d.month - 1]} ${d.year}';
          }()
        ),
      _ => ('Every ${e.day}', 'Weekly'),
    };

Future<ScheduleSheetResult?> showScheduleEventSheet(
  BuildContext context, {
  ScheduleEntry? entry,
  required DateTime date,
  String? subject,
  String? planTitle,
  bool canEdit = false,
  bool addedByYou = false,
  String? readOnlyHint,
  List<LessonPlanOption> lessonPlans = const [],
  String? initialStartTime,
  String? initialEndTime,
}) {
  return showModalBottomSheet<ScheduleSheetResult>(
    context: context,
    isScrollControlled: true, // grow with the form / keyboard
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => ScheduleEventSheet(
      entry: entry,
      date: date,
      subject: subject,
      planTitle: planTitle,
      canEdit: canEdit,
      addedByYou: addedByYou,
      readOnlyHint: readOnlyHint,
      lessonPlans: lessonPlans,
      initialStartTime: initialStartTime,
      initialEndTime: initialEndTime,
    ),
  );
}

class ScheduleEventSheet extends StatefulWidget {
  const ScheduleEventSheet({
    super.key,
    required this.entry,
    required this.date,
    this.subject,
    this.planTitle,
    this.canEdit = false,
    this.addedByYou = false,
    this.readOnlyHint,
    this.lessonPlans = const [],
    this.initialStartTime,
    this.initialEndTime,
  });

  final ScheduleEntry? entry; // null = create
  final DateTime date;
  final String? subject;
  final String? planTitle;
  final bool canEdit;
  final bool addedByYou;
  final String? readOnlyHint;
  final List<LessonPlanOption> lessonPlans;
  final String? initialStartTime;
  final String? initialEndTime;

  @override
  State<ScheduleEventSheet> createState() => _ScheduleEventSheetState();
}

class _ScheduleEventSheetState extends State<ScheduleEventSheet> {
  late bool _editing;

  // Form state. Seeded from the entry each time edit mode is entered, so a
  // Cancel throws away half-made changes.
  final _formKey = GlobalKey<FormState>();
  final _labelController = TextEditingController();
  late TimeOfDay _start;
  late TimeOfDay _end;
  late String _color;
  late String _recurrence;
  String? _lessonPlanId;
  String? _timeError;

  bool get _isCreate => widget.entry == null;

  @override
  void initState() {
    super.initState();
    _editing = _isCreate;
    _seedForm();
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  static TimeOfDay _parse(String hhmm) {
    final parts = hhmm.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  static String _format(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  void _seedForm() {
    final e = widget.entry;
    _labelController.text = e?.label ?? '';
    _start = _parse(e?.startTime ?? widget.initialStartTime ?? '08:00');
    _end = _parse(e?.endTime ?? widget.initialEndTime ?? '09:00');
    _color = e?.color ?? defaultScheduleColorHex;
    // Untouched new events stay 'weekly', the long-standing default.
    _recurrence = e?.recurrence ?? 'weekly';
    // Keep the current attachment only if it's among the offered plans.
    final ids = widget.lessonPlans.map((p) => p.id).toSet();
    _lessonPlanId = ids.contains(e?.lessonPlanId) ? e!.lessonPlanId : null;
    _timeError = null;
  }

  DateTime get _anchor => widget.entry?.anchorDate ?? widget.date;

  Future<void> _pickTime({required bool start}) async {
    final picked = await showTimePicker(context: context, initialTime: start ? _start : _end);
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        // Moving the start keeps the event's length, so the end follows.
        final length = _minutes(_end) - _minutes(_start);
        _start = picked;
        if (length > 0) {
          final endMin = (_minutes(picked) + length).clamp(0, 23 * 60 + 59);
          _end = TimeOfDay(hour: endMin ~/ 60, minute: endMin % 60);
        }
      } else {
        _end = picked;
      }
      _timeError = null;
    });
  }

  void _save() {
    final nameOk = _formKey.currentState!.validate();
    final timeOk = _minutes(_end) > _minutes(_start);
    setState(() {
      _timeError = timeOk ? null : 'End time must be after the start time';
    });
    if (!nameOk || !timeOk) return;
    Navigator.of(context).pop(ScheduleEntrySaved(
      startTime: _format(_start),
      endTime: _format(_end),
      label: _labelController.text.trim(),
      color: _color,
      recurrence: _recurrence,
      anchorDate: _anchor,
      lessonPlanId: _lessonPlanId,
    ));
  }

  Future<void> _delete() async {
    final entry = widget.entry!;
    if (!await confirmDelete(context, message: 'Delete "${entry.label}"?')) return;
    if (mounted) Navigator.of(context).pop(ScheduleEntryDeleted());
  }

  void _cancelEdit() {
    if (_isCreate) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _seedForm();
      _editing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      // White, thin-bordered fields and dark-rose buttons (AppTheme.lightForm).
      data: AppTheme.lightForm(Theme.of(context)),
      child: SafeArea(
        top: false,
        child: Padding(
          // Lift the sheet above the keyboard while typing the name.
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Grabber: the visual cue that the sheet can be dragged away.
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.fieldBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // AnimatedSize: the switch between summary and form grows
                // or shrinks the sheet smoothly instead of jumping.
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _editing ? _buildForm(context) : _buildSummary(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _titleRow(Widget leading, String title) {
    return Row(
      children: [
        leading,
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
                fontSize: 21, fontWeight: FontWeight.w800, color: AppTheme.onAccent),
          ),
        ),
        IconButton(
          tooltip: 'Close',
          color: AppTheme.mutedText,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  // ---------- view mode ----------
  Widget _buildSummary(BuildContext context) {
    final entry = widget.entry!;
    final date = widget.date;
    final duration = scheduleDurationLabel(entry.startTime, entry.endTime);
    final dateLabel =
        '${_weekdayNames[date.weekday - 1]}, ${date.day} ${_monthAbbrev[date.month - 1]}';
    final (repeatHead, repeatDetail) = _repeatSummary(entry, date);
    final subject = widget.subject;

    return Column(
      key: const ValueKey('event-sheet-summary'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titleRow(
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: entry.displayColor, shape: BoxShape.circle),
            ),
          ),
          entry.label,
        ),
        const SizedBox(height: 8),
        _InfoRow(
          icon: Icons.schedule,
          title: '${entry.startTime} – ${entry.endTime}',
          detail: duration.isEmpty ? dateLabel : '$dateLabel · $duration',
        ),
        _InfoRow(icon: Icons.repeat, title: repeatHead, detail: repeatDetail),
        if (widget.addedByYou) const _InfoRow(icon: Icons.person_outline, title: 'Added by you'),
        if (entry.lessonPlanId != null) ...[
          const SizedBox(height: 6),
          const _SectionLabel('LESSON PLAN'),
          const SizedBox(height: 8),
          Material(
            key: const Key('event-sheet-plan'),
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppTheme.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(context).pop(ScheduleOpenPlan()),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    SubjectTile(name: subject, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.planTitle ?? 'Lesson plan',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.onAccent,
                            ),
                          ),
                          Text(
                            subject == null
                                ? 'Approved lesson plan'
                                : '$subject · Approved lesson plan',
                            style: const TextStyle(fontSize: 12, color: AppTheme.mutedText),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppTheme.mutedText),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        if (widget.canEdit)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _delete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB3261E),
                    side: const BorderSide(color: Color(0xFFB3261E), width: 1.5),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => setState(() {
                    _seedForm();
                    _editing = true;
                  }),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
              ),
            ],
          )
        else if (widget.readOnlyHint != null)
          Text(
            widget.readOnlyHint!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppTheme.mutedText),
          ),
      ],
    );
  }

  // ---------- edit / create mode ----------
  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('event-sheet-form'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titleRow(const SizedBox.shrink(), _isCreate ? 'New event' : 'Edit event'),
          const SizedBox(height: 8),
          const _FieldLabel('Event name'),
          TextFormField(
            key: const Key('event-name'),
            controller: _labelController,
            autofocus: _isCreate,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'e.g. Morning circle'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Please enter an event name' : null,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _TimeTile(
                  key: const Key('event-start'),
                  label: 'Starts',
                  time: _format(_start),
                  onTap: () => _pickTime(start: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TimeTile(
                  key: const Key('event-end'),
                  label: 'Ends',
                  time: _format(_end),
                  error: _timeError != null,
                  onTap: () => _pickTime(start: false),
                ),
              ),
            ],
          ),
          if (_timeError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(_timeError!,
                  style: const TextStyle(fontSize: 12, color: Color(0xFFB3261E))),
            ),
          const SizedBox(height: 14),
          const _FieldLabel('Repeats'),
          _RepeatPicker(
            value: _recurrence,
            onChanged: (v) => setState(() => _recurrence = v),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.info_outline, size: 14, color: AppTheme.mutedText),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _recurrenceHelp(_recurrence, _anchor, day: widget.entry?.day),
                  style: const TextStyle(fontSize: 12, color: AppTheme.mutedText),
                ),
              ),
            ],
          ),
          // Attach an approved lesson plan (only when the class has any);
          // its subject then shows on the event.
          if (widget.lessonPlans.isNotEmpty) ...[
            const SizedBox(height: 14),
            const _FieldLabel('Lesson plan'),
            AppDropdownField<String?>(
              value: _lessonPlanId,
              decoration: const InputDecoration(),
              items: [
                const DropdownMenuItem(value: null, child: Text('None')),
                for (final plan in widget.lessonPlans)
                  DropdownMenuItem(value: plan.id, child: Text(plan.label)),
              ],
              onChanged: (v) => setState(() => _lessonPlanId = v),
            ),
          ],
          const SizedBox(height: 14),
          const _FieldLabel('Colour'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final swatch in scheduleColorPalette.entries)
                _ColorSwatch(
                  key: Key('color-swatch-${swatch.key}'),
                  name: swatch.key,
                  hex: swatch.value,
                  selected: swatch.value == _color,
                  onTap: () => setState(() => _color = swatch.value),
                ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _cancelEdit,
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: Text(_isCreate ? 'Add event' : 'Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.9,
          color: AppTheme.mutedText,
        ),
      );
}

// Label above a field (same as the lesson plan editor's).
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.onAccent)),
      );
}

// Icon tile + a bold line + an optional muted detail line.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.title, this.detail});

  final IconData icon;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.barTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppTheme.onAccent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.onAccent)),
                if (detail != null)
                  Text(detail!, style: const TextStyle(fontSize: 12, color: AppTheme.mutedText)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// A tappable "Starts 08:00" box that opens the time picker. Looks like the
// other fields (white, thin border) so it reads as an input.
class _TimeTile extends StatelessWidget {
  const _TimeTile({
    super.key,
    required this.label,
    required this.time,
    required this.onTap,
    this.error = false,
  });

  final String label;
  final String time;
  final VoidCallback onTap;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: error ? const Color(0xFFB3261E) : AppTheme.fieldBorder,
          width: error ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.mutedText)),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.schedule, size: 16, color: AppTheme.onAccent),
                  const SizedBox(width: 6),
                  Text(time,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.onAccent)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Once / Daily / Weekly as a segmented control instead of a dropdown: all
// three options are visible at once and one tap picks, rather than open,
// read, pick. The selected segment is a raised white pill on a pink track.
class _RepeatPicker extends StatelessWidget {
  const _RepeatPicker({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static const _options = [('once', 'Once'), ('daily', 'Daily'), ('weekly', 'Weekly')];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.barTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Row(
        children: [
          for (final (key, label) in _options)
            Expanded(
              child: GestureDetector(
                key: Key('repeat-$key'),
                onTap: () => onChanged(key),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: value == key ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: value == key
                        ? [
                            BoxShadow(
                              color: AppTheme.onAccent.withValues(alpha: 0.10),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: value == key ? FontWeight.w800 : FontWeight.w600,
                      color: value == key ? AppTheme.onAccent : AppTheme.mutedText,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    super.key,
    required this.name,
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = colorFromScheduleHex(hex);
    return Tooltip(
      message: name,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            // A white gap then a dark ring: reads as "picked" on any swatch.
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: selected
                ? const [BoxShadow(color: AppTheme.onAccent, spreadRadius: 2)]
                : null,
          ),
          alignment: Alignment.center,
          child: selected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
        ),
      ),
    );
  }
}
