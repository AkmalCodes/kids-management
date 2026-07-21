import 'package:flutter/material.dart';
import '../../core/models/schedule.dart';

sealed class ScheduleEntryFormResult {}

class ScheduleEntrySaved extends ScheduleEntryFormResult {
  ScheduleEntrySaved({required this.startTime, required this.endTime, required this.label});
  final String startTime;
  final String endTime;
  final String label;
}

class ScheduleEntryDeleted extends ScheduleEntryFormResult {}

// Pass `existing` to edit/delete a real entry, or omit it to add a new one
// (optionally pre-filled via initialStartTime/initialEndTime — e.g. the
// hour the user tapped in DayTimetable). Returns null if the user cancels.
Future<ScheduleEntryFormResult?> showScheduleEntryFormDialog(
  BuildContext context, {
  ScheduleEntry? existing,
  String? initialStartTime,
  String? initialEndTime,
}) {
  return showDialog<ScheduleEntryFormResult>(
    context: context,
    builder: (_) => _ScheduleEntryFormDialog(
      existing: existing,
      initialStartTime: initialStartTime,
      initialEndTime: initialEndTime,
    ),
  );
}

class _ScheduleEntryFormDialog extends StatefulWidget {
  const _ScheduleEntryFormDialog({
    this.existing,
    this.initialStartTime,
    this.initialEndTime,
  });

  final ScheduleEntry? existing;
  final String? initialStartTime;
  final String? initialEndTime;

  @override
  State<_ScheduleEntryFormDialog> createState() => _ScheduleEntryFormDialogState();
}

class _ScheduleEntryFormDialogState extends State<_ScheduleEntryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelController;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;

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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Event' : 'Add Event'),
      content: Form(
        key: _formKey,
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
          ],
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
