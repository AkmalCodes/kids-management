import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/staff_attendance.dart';
import '../../../core/controllers/staff_attendance_controller.dart';
import '../../../shared/widgets/app_loader.dart';

// Lets a teacher mark their own attendance for today, from their Profile
// tab. The only control this schema piece of work ships -- the director-
// facing surface (marking any teacher, seeing every teacher's status) is a
// later plan's job. See
// docs/superpowers/specs/2026-09-02-staff-attendance-schema-design.md.
//
// Renders nothing for a non-teacher, and nothing for a teacher with no
// center_id (AppUser.centerId is nullable; markAttendance requires one).
// ProfileScreen decides whether to show this at all by role; the centerId
// check lives here since it is about this control's own precondition, not
// about who should see it.
class StaffAttendanceToggle extends ConsumerStatefulWidget {
  const StaffAttendanceToggle({super.key});

  @override
  ConsumerState<StaffAttendanceToggle> createState() => _StaffAttendanceToggleState();
}

class _StaffAttendanceToggleState extends ConsumerState<StaffAttendanceToggle> {
  // Captured once, like mark_attendance_screen.dart's _todayDate: a mark
  // made right before midnight must not silently target a different day
  // than what was on screen when the widget built.
  late final DateTime _todayDate = DateTime.now();
  late final String _today = _todayDate.toIso8601String().substring(0, 10);

  late Future<StaffAttendance?> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<StaffAttendance?> _load() async {
    final user = await ref.read(currentUserProvider.future);
    // Mirrors build()'s bail-out: no point fetching when there is nothing
    // useful to show, and a centerless user can never have a row anyway
    // (markAttendance requires a non-null center_id).
    if (user == null || user.role != 'teacher' || user.centerId == null) return null;
    final all = await ref.read(staffAttendanceControllerProvider).fetchForDate(_today);
    // fetchForDate returns every staff member's row for the day -- keep
    // only this user's own.
    for (final record in all) {
      if (record.staffId == user.id) return record;
    }
    return null;
  }

  Future<void> _setStatus(AttendanceStatus status, StaffAttendance? existing) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null || user.centerId == null) return;
    setState(() => _busy = true);
    try {
      final updated = await ref.read(staffAttendanceControllerProvider).markAttendance(
            staffId: user.id,
            centerId: user.centerId!,
            date: _today,
            status: status,
            actorUid: user.id,
            existingId: existing?.id,
          );
      if (mounted) {
        setState(() {
          _future = Future.value(updated);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save attendance: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;
    if (user == null || user.role != 'teacher' || user.centerId == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<StaffAttendance?>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: AppLoader(size: 20)),
          );
        }
        final existing = snapshot.data;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Today's attendance", style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final status in const [AttendanceStatus.present, AttendanceStatus.absent])
                    ChoiceChip(
                      label: Text(status == AttendanceStatus.present ? 'Present' : 'Absent'),
                      selected: existing?.status == status,
                      onSelected: _busy ? null : (_) => _setStatus(status, existing),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
