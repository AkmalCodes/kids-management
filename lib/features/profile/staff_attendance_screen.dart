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
  // it built, not whatever "today" becomes mid-tap. Local (not .toUtc()): the
  // calendar date the teacher is working is the local one.
  late final String _today = DateTime.now().toIso8601String().substring(0, 10);

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
    // Capture now() once: the value shown in the confirm dialog is the value
    // handed to the controller, so the recorded time can't drift from what the
    // teacher confirmed (payroll data).
    final now = DateTime.now();
    if (!await _confirm('Confirm clock-in at ${hourMinute(now)}?')) return;
    setState(() => _busy = true);
    try {
      final updated = await ref.read(staffAttendanceControllerProvider).clockIn(
            staffId: user.id,
            centerId: user.centerId!,
            date: _today,
            actorUid: user.id,
            at: now,
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
    // Same capture-once rule as _clockIn: confirmed time == recorded time.
    final now = DateTime.now();
    if (!await _confirm('Confirm clock-out at ${hourMinute(now)}?')) return;
    setState(() => _busy = true);
    try {
      final updated = await ref.read(staffAttendanceControllerProvider).clockOut(
            id: existing.id,
            actorUid: user.id,
            at: now,
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
    // Watched here at the top of build(), not inside the FutureBuilder closure:
    // watching from a nested builder is a riverpod_lint smell and rebuild-order
    // hazard. A null row from _load means "nothing recorded yet" for a normal
    // teacher, but _load also returns null for a non-teacher or a teacher with
    // no center_id -- and clockIn needs a center. Gate the Clock in button on
    // exactly the predicate _load guards on, so such a user sees the times
    // (all --:--) but no dead button.
    final u = ref.watch(currentUserProvider).value;
    final canClockIn = u != null && u.role == 'teacher' && u.centerId != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: FutureBuilder<StaffAttendance?>(
        future: _record,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: AppLoader());
          }
          if (snapshot.hasError) {
            // Without this branch a failed load falls through to the data
            // branch with snapshot.data == null, which renders identically to
            // "nothing recorded yet" -- a silent lie. Show the failure + a
            // retry instead.
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Couldn't load today's attendance."),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _record = _load();
                      });
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          final row = snapshot.data;
          final clockedIn = row?.clockInAt != null;
          final clockedOut = row?.clockOutAt != null;

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
