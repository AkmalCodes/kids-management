import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/staff_attendance.dart';
import '../../core/controllers/staff_attendance_controller.dart';
import '../../shared/util/date_display.dart';
import '../../shared/widgets/app_loader.dart';

// A teacher's clock-in / clock-out for today, reached from the Profile tab.
// Replaces the old Present/Absent chip toggle: the recorded times feed HR and
// (later) payroll, so each write goes behind a confirm step and, once both
// times are set, the day is locked -- no re-clocking, no editing here. See
// docs/superpowers/specs/2026-09-02-staff-clock-in-out-design.md.
//
// ProfileScreen only shows the entry button to a teacher; the centerId guard
// lives here because it is this screen's own precondition (clockIn needs a
// non-null center_id), not a question of who may see the button.
class StaffAttendanceScreen extends ConsumerStatefulWidget {
  const StaffAttendanceScreen({super.key});

  @override
  ConsumerState<StaffAttendanceScreen> createState() => _StaffAttendanceScreenState();
}

class _StaffAttendanceScreenState extends ConsumerState<StaffAttendanceScreen> {
  // Captured once, like mark_attendance_screen.dart's _today: a clock action
  // taken right before midnight must target the day that was on screen when
  // it built, not whatever "today" becomes mid-tap.
  final DateTime _todayDate = DateTime.now();
  late final String _today = _todayDate.toIso8601String().substring(0, 10);

  late Future<StaffAttendance?> _record;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _record = _load();
  }

  Future<StaffAttendance?> _load() async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null || user.role != 'teacher' || user.centerId == null) return null;
    final all = await ref.read(staffAttendanceControllerProvider).fetchForDate(_today);
    // fetchForDate returns every staff member's row for the day -- keep only
    // this user's own.
    for (final row in all) {
      if (row.staffId == user.id) return row;
    }
    return null;
  }

  Future<bool> _confirm(String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _clockIn(StaffAttendance? existing) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null || user.centerId == null) return;
    if (!await _confirm('Confirm clock-in at ${hourMinute(DateTime.now())}?')) return;
    setState(() => _busy = true);
    try {
      final updated = await ref.read(staffAttendanceControllerProvider).clockIn(
            staffId: user.id,
            centerId: user.centerId!,
            date: _today,
            actorUid: user.id,
            existingId: existing?.id,
          );
      if (!mounted) return;
      setState(() {
        _record = Future.value(updated);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not clock in: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clockOut(StaffAttendance existing) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;
    if (!await _confirm('Confirm clock-out at ${hourMinute(DateTime.now())}?')) return;
    setState(() => _busy = true);
    try {
      final updated = await ref.read(staffAttendanceControllerProvider).clockOut(
            id: existing.id,
            actorUid: user.id,
          );
      if (!mounted) return;
      setState(() {
        _record = Future.value(updated);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not clock out: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: FutureBuilder<StaffAttendance?>(
        future: _record,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: AppLoader());
          }
          final row = snapshot.data;
          final clockedIn = row?.clockInAt != null;
          final clockedOut = row?.clockOutAt != null;
          // A null row means "nothing recorded yet" for a normal teacher, but
          // _load also returns null for a teacher with no center_id -- and
          // clockIn requires one. Gate the Clock in button on it so a
          // centerless teacher sees the times (all --:--) but no dead button.
          final canClockIn =
              ref.watch(currentUserProvider).value?.centerId != null;

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Today', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(
                isoWithWeekday(_today),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),
              _TimeRow(
                label: 'Clocked in',
                value: clockedIn ? hourMinute(row!.clockInAt!.toLocal()) : '--:--',
              ),
              const SizedBox(height: 8),
              _TimeRow(
                label: 'Clocked out',
                value: clockedOut ? hourMinute(row!.clockOutAt!.toLocal()) : '--:--',
              ),
              const SizedBox(height: 24),
              if (!clockedIn && canClockIn)
                FilledButton(
                  onPressed: _busy ? null : () => _clockIn(row),
                  child: const Text('Clock in'),
                )
              else if (clockedIn && !clockedOut)
                FilledButton(
                  onPressed: _busy ? null : () => _clockOut(row!),
                  child: const Text('Clock out'),
                ),
              // Both set -> no button; the day is locked and the two _TimeRows
              // above already show the recorded times as plain text.
            ],
          );
        },
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyLarge),
        Text(value, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }
}
