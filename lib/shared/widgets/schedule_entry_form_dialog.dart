import 'package:flutter/material.dart';
import '../../core/constants/schedule_colors.dart';
import '../../core/models/schedule.dart';

sealed class ScheduleEntryFormResult {}

class ScheduleEntrySaved extends ScheduleEntryFormResult {
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
  // The calendar date the recurrence rule is measured from. The dialog
  // has no UI to change it — it echoes back the anchor it was handed.
  final DateTime anchorDate;
  // The approved lesson plan attached to this event, or null for none.
  final String? lessonPlanId;
}

// Weekday / month name lists mirroring day_schedule_screen.dart, used only to
// phrase the "Repeats" helper text.
const _weekdayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];
const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _weekdayName(int weekday) => _weekdayNames[weekday - 1]; // Monday == 1
String _monthName(int month) => _monthNames[month - 1];

// A plain-language sentence describing what the current recurrence + anchor
// date actually mean, shown under the "Repeats" dropdown.
// For weekly, prefers the entry's own day (when editing) over the anchor's weekday.
String _recurrenceHelp(String recurrence, DateTime anchor, {String? day}) {
  switch (recurrence) {
    case 'once':
      return 'Occurs once on ${anchor.day} ${_monthName(anchor.month)} ${anchor.year}';
    case 'daily':
      return 'Repeats every weekday';
    case 'weekly':
    default:
      // Use the entry's own day if provided (when editing); else fall back to anchor's weekday.
      final weekday = day ?? _weekdayName(anchor.weekday);
      return 'Repeats every $weekday';
  }
}

class ScheduleEntryDeleted extends ScheduleEntryFormResult {}

// One attachable lesson plan, pre-labelled by the caller (title · subject) so
// this dialog stays decoupled from the subjects list.
typedef LessonPlanOption = ({String id, String label});

// Pass `existing` to edit/delete a real entry, or omit it to add a new one
// (optionally pre-filled via initialStartTime/initialEndTime — e.g. the
// hour the user tapped in DayTimetable). `lessonPlans` are the approved plans
// attachable to this event (empty hides the picker). Returns null on cancel.
Future<ScheduleEntryFormResult?> showScheduleEntryFormDialog(
  BuildContext context, {
  required DateTime anchorDate,
  ScheduleEntry? existing,
  String? initialStartTime,
  String? initialEndTime,
  List<LessonPlanOption> lessonPlans = const [],
}) {
  return showDialog<ScheduleEntryFormResult>(
    context: context,
    builder: (_) => _ScheduleEntryFormDialog(
      anchorDate: anchorDate,
      existing: existing,
      initialStartTime: initialStartTime,
      initialEndTime: initialEndTime,
      lessonPlans: lessonPlans,
    ),
  );
}

class _ScheduleEntryFormDialog extends StatefulWidget {
  const _ScheduleEntryFormDialog({
    required this.anchorDate,
    this.existing,
    this.initialStartTime,
    this.initialEndTime,
    this.lessonPlans = const [],
  });

  final DateTime anchorDate;
  final ScheduleEntry? existing;
  final String? initialStartTime;
  final String? initialEndTime;
  final List<LessonPlanOption> lessonPlans;

  @override
  State<_ScheduleEntryFormDialog> createState() => _ScheduleEntryFormDialogState();
}

class _ScheduleEntryFormDialogState extends State<_ScheduleEntryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelController;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late String _selectedColor;
  // 'once' / 'daily' / 'weekly'. Seeded from the edited entry,
  // else 'weekly' so an untouched dialog keeps today's behaviour.
  late String _recurrence;
  String? _lessonPlanId;

  static TimeOfDay _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  static String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _labelController = TextEditingController(text: existing?.label ?? '');
    _startTime = existing != null
        ? _parseTime(existing.startTime)
        : _parseTime(widget.initialStartTime ?? '08:00');
    _endTime = existing != null
        ? _parseTime(existing.endTime)
        : _parseTime(widget.initialEndTime ?? '09:00');
    _selectedColor = existing?.color ?? defaultScheduleColorHex;
    _recurrence = existing?.recurrence ?? 'weekly';
    // Keep the current attachment only if it's among the offered plans.
    final planIds = widget.lessonPlans.map((p) => p.id).toSet();
    _lessonPlanId = planIds.contains(existing?.lessonPlanId) ? existing!.lessonPlanId : null;
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(context: context, initialTime: _startTime);
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(context: context, initialTime: _endTime);
    if (picked != null) setState(() => _endTime = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      ScheduleEntrySaved(
        startTime: _formatTime(_startTime),
        endTime: _formatTime(_endTime),
        label: _labelController.text.trim(),
        color: _selectedColor,
        recurrence: _recurrence,
        anchorDate: widget.anchorDate,
        lessonPlanId: _lessonPlanId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Event' : 'Create Event'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            TextFormField(
              controller: _labelController,
              decoration: const InputDecoration(labelText: 'Event name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Please enter an event name' : null,
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _pickStartTime,
              icon: const Icon(Icons.schedule),
              label: Text('Start: ${_formatTime(_startTime)}'),
            ),
            TextButton.icon(
              onPressed: _pickEndTime,
              icon: const Icon(Icons.schedule),
              label: Text('End: ${_formatTime(_endTime)}'),
            ),
            const SizedBox(height: 12),
            // How often the event repeats. Defaults to 'weekly' (unchanged
            // behaviour). The anchor date is fixed by the caller — this only
            // picks the frequency; the helper text spells out the concrete rule.
            DropdownButtonFormField<String>(
              isExpanded: true,
              borderRadius: BorderRadius.circular(16),
              initialValue: _recurrence,
              decoration: const InputDecoration(labelText: 'Repeats'),
              items: const [
                DropdownMenuItem(value: 'once', child: Text('Once')),
                DropdownMenuItem(value: 'daily', child: Text('Daily')),
                DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
              ],
              onChanged: (v) => setState(() => _recurrence = v!),
            ),
            const SizedBox(height: 4),
            Text(
              _recurrenceHelp(_recurrence, widget.anchorDate, day: widget.existing?.day),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            // Attach an approved lesson plan (only shown if any exist for the
            // class); its subject then appears on the event.
            if (widget.lessonPlans.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                borderRadius: BorderRadius.circular(16),
                initialValue: _lessonPlanId,
                decoration: const InputDecoration(labelText: 'Lesson plan'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None')),
                  for (final plan in widget.lessonPlans)
                    DropdownMenuItem(value: plan.id, child: Text(plan.label)),
                ],
                onChanged: (v) => setState(() => _lessonPlanId = v),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final swatch in scheduleColorPalette.entries)
                  _ColorSwatch(
                    key: Key('color-swatch-${swatch.key}'),
                    name: swatch.key,
                    hex: swatch.value,
                    selected: swatch.value == _selectedColor,
                    onTap: () => setState(() => _selectedColor = swatch.value),
                  ),
              ],
            ),
          ],
        ),
        ),
      ),
      actions: [
        if (isEditing)
          TextButton(
            onPressed: () => Navigator.of(context).pop(ScheduleEntryDeleted()),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
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
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: selected
                ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 2)
                : null,
          ),
          alignment: Alignment.center,
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: 18)
              : null,
        ),
      ),
    );
  }
}
