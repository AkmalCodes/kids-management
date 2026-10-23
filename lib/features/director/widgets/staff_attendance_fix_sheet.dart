import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/controllers/profile_controller.dart';
import '../../../core/controllers/staff_attendance_controller.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/staff_attendance.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/attendance_status_chip.dart';
import '../../../shared/widgets/signed_avatar.dart';

// The director fixing one teacher's attendance for one day (screen design
// AA4, Teachers view). What it can do, by design (spec 2026-10-23):
//
// - set the day's status (present / late / absent / excused) and a note;
// - record a MISSING clock-in or clock-out at a chosen time -- e.g. a
//   teacher who forgot to clock in. A time that is already recorded is shown
//   locked: overwriting payroll times is deliberately not offered (the
//   controller's clockIn/clockOut also refuse to overwrite).
//
// Authorisation is RLS (staff_attendance_insert/update allow a director only
// for teachers in their own centre); this sheet just doesn't offer more.
// Every saved write is reported through onSaved so the list behind updates.
Future<void> showStaffAttendanceFixSheet(
  BuildContext context, {
  required AppUser teacher,
  required String date, // YYYY-MM-DD
  required String dateLabel,
  required StaffAttendance? existing,
  required ValueChanged<StaffAttendance> onSaved,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => StaffAttendanceFixSheet(
      teacher: teacher,
      date: date,
      dateLabel: dateLabel,
      existing: existing,
      onSaved: onSaved,
    ),
  );
}

class StaffAttendanceFixSheet extends ConsumerStatefulWidget {
  const StaffAttendanceFixSheet({
    super.key,
    required this.teacher,
    required this.date,
    required this.dateLabel,
    required this.existing,
    required this.onSaved,
  });

  final AppUser teacher;
  final String date;
  final String dateLabel;
  final StaffAttendance? existing;
  final ValueChanged<StaffAttendance> onSaved;

  @override
  ConsumerState<StaffAttendanceFixSheet> createState() => _StaffAttendanceFixSheetState();
}

class _StaffAttendanceFixSheetState extends ConsumerState<StaffAttendanceFixSheet> {
  late StaffAttendance? _row = widget.existing;
  late AttendanceStatus _status = widget.existing?.status ?? AttendanceStatus.present;
  late final TextEditingController _note = TextEditingController(text: widget.existing?.notes ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _apply(StaffAttendance saved) {
    setState(() {
      _row = saved;
      _status = saved.status;
    });
    widget.onSaved(saved);
  }

  Future<void> _run(Future<void> Function(AppUser me) action) async {
    final me = ref.read(currentUserProvider).value;
    if (me == null || me.centerId == null) {
      setState(() => _error = "Can't save: your account has no centre.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(me);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveStatus() => _run((me) async {
        final saved = await ref.read(staffAttendanceControllerProvider).markAttendance(
              staffId: widget.teacher.id,
              centerId: me.centerId!,
              date: widget.date,
              status: _status,
              actorUid: me.id,
              existingId: _row?.id,
              notes: _note.text.trim(),
            );
        _apply(saved);
      });

  // Pick a time on the viewed day, confirm, then record it. Returns null if
  // the director backed out at any step.
  Future<DateTime?> _pickTime({required String what, required TimeOfDay initial}) async {
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null || !mounted) return null;
    final d = DateTime.parse(widget.date);
    final at = DateTime(d.year, d.month, d.day, picked.hour, picked.minute);
    final hhmm = formatClock(at);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Record $what at $hhmm?'),
        content: Text("This is ${widget.teacher.name}'s $what for ${widget.dateLabel}. "
            "Once recorded it can't be changed."),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Record')),
        ],
      ),
    );
    return ok == true ? at : null;
  }

  Future<void> _recordIn() async {
    final at = await _pickTime(what: 'clock-in', initial: const TimeOfDay(hour: 8, minute: 0));
    if (at == null) return;
    await _run((me) async {
      final saved = await ref.read(staffAttendanceControllerProvider).clockIn(
            staffId: widget.teacher.id,
            centerId: me.centerId!,
            date: widget.date,
            actorUid: me.id,
            at: at,
            existingId: _row?.id,
          );
      _apply(saved);
    });
  }

  Future<void> _recordOut() async {
    final row = _row;
    final inAt = row?.clockInAt?.toLocal();
    if (row == null || inAt == null) return;
    final at = await _pickTime(what: 'clock-out', initial: const TimeOfDay(hour: 17, minute: 0));
    if (at == null) return;
    // The database also refuses this (clock_out_at > clock_in_at), but say
    // why here instead of showing a raw constraint error.
    if (!at.isAfter(inAt)) {
      setState(() => _error = 'Clock-out must be after the clock-in (${formatClock(inAt)}).');
      return;
    }
    await _run((me) async {
      final saved = await ref.read(staffAttendanceControllerProvider).clockOut(
            id: row.id,
            actorUid: me.id,
            at: at,
          );
      _apply(saved);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(currentUserProvider); // subscribe before anything is tappable
    final t = widget.teacher;
    final inAt = _row?.clockInAt;
    final outAt = _row?.clockOutAt;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: AppTheme.fieldBorder, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  SignedAvatar(
                    urlProvider: t.avatarPath == null ? null : signedAvatarUrlProvider(t.avatarPath!),
                    radius: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.name,
                            style: const TextStyle(
                                fontSize: 19, fontWeight: FontWeight.w800, color: AppTheme.onAccent)),
                        Text(widget.dateLabel, style: const TextStyle(fontSize: 12, color: AppTheme.mutedText)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    color: AppTheme.mutedText,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.hairline),
                ),
                child: Column(
                  children: [
                    _ClockRow(
                      label: 'Clocked in',
                      time: inAt,
                      action: inAt == null
                          ? TextButton(
                              key: const Key('record-clock-in'),
                              onPressed: _busy ? null : _recordIn,
                              child: const Text('Record'),
                            )
                          : null,
                    ),
                    const Divider(height: 1, color: AppTheme.hairline),
                    _ClockRow(
                      label: 'Clocked out',
                      time: outAt,
                      action: outAt == null && inAt != null
                          ? TextButton(
                              key: const Key('record-clock-out'),
                              onPressed: _busy ? null : _recordOut,
                              child: const Text('Record'),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              const Text('Recorded times are locked and can\'t be changed.',
                  style: TextStyle(fontSize: 11, color: AppTheme.mutedText)),
              const SizedBox(height: 16),
              const Text('STATUS',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.9, color: AppTheme.mutedText)),
              const SizedBox(height: 8),
              AttendanceStatusPicker(value: _status, onChanged: (s) => setState(() => _status = s)),
              const SizedBox(height: 12),
              Theme(
                data: AppTheme.lightForm(Theme.of(context)),
                child: TextField(
                  key: const Key('staff-note'),
                  controller: _note,
                  minLines: 1,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Note (optional), e.g. "MC"'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(fontSize: 12, color: Color(0xFFB3261E))),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _saveStatus,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.onAccent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Save status'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClockRow extends StatelessWidget {
  const _ClockRow({required this.label, required this.time, this.action});

  final String label;
  final DateTime? time;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = time;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.onAccent)),
          ),
          if (t != null) ...[
            Text(formatClock(t),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.onAccent)),
            const SizedBox(width: 8),
            const Icon(Icons.lock_outline, size: 16, color: AppTheme.mutedText),
          ] else
            action ?? const Text('—', style: TextStyle(fontSize: 15, color: AppTheme.mutedText)),
        ],
      ),
    );
  }
}
