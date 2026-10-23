import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/staff_attendance.dart';
import '../../core/controllers/staff_attendance_controller.dart';
import '../../shared/util/date_display.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_loader.dart';

// A teacher's clock-in / clock-out for today, reached from the Attendance tab's
// Teachers grid (a teacher tapping their own tile). Replaces the old
// Present/Absent chip toggle: the recorded times feed HR and (later) payroll, so
// each write goes behind a confirm step and, once both times are set, the day is
// locked -- no re-clocking, no editing here. See
// docs/superpowers/specs/2026-09-02-staff-clock-in-out-design.md.
//
// The teacher-only gating is that the Teachers grid exists only on the teacher
// attendance screen; the centerId guard lives here because it is this screen's
// own precondition (clockIn needs a non-null center_id), not a question of who
// may see the grid.
//
// Look: screen design AA3 (Figma "Screen designs"): a hero card with today's
// hours, the two times as rows (locked once recorded), one button for the
// next action, and the rest of this week below.
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
  // Earlier days this week (Mon..yesterday). Optional extra: a failure just
  // hides the section, it never blocks clocking.
  late Future<List<StaffAttendance>> _week;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _record = _load();
    _week = _loadWeek();
  }

  Future<List<StaffAttendance>> _loadWeek() async {
    try {
      final user = await ref.read(currentUserProvider.future);
      if (user == null) return const [];
      final today = DateTime.parse(_today);
      if (today.weekday == DateTime.monday) return const []; // nothing earlier
      final monday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
      final yesterday = DateTime(today.year, today.month, today.day - 1);
      String iso(DateTime d) => d.toIso8601String().substring(0, 10);
      return await ref
          .read(staffAttendanceControllerProvider)
          .fetchForStaffBetween(staffId: user.id, from: iso(monday), to: iso(yesterday));
    } catch (_) {
      return const [];
    }
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

  static const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  // "8 h 37 min" / "45 min".
  static String _hours(Duration d) {
    final m = d.inMinutes;
    if (m < 60) return '$m min';
    return m % 60 == 0 ? '${m ~/ 60} h' : '${m ~/ 60} h ${m % 60} min';
  }

  @override
  Widget build(BuildContext context) {
    // Watched here at the top of build(), not inside the FutureBuilder closure:
    // watching from a nested builder is a riverpod_lint smell and rebuild-order
    // hazard. A null row from _load means "nothing recorded yet" for a normal
    // teacher, but _load also returns null for a non-teacher or a teacher with
    // no center_id -- and clockIn needs a center. Gate the Clock in button on
    // exactly the predicate _load guards on, so such a user sees the times
    // but no dead button.
    final u = ref.watch(currentUserProvider).value;
    final canClockIn = u != null && u.role == 'teacher' && u.centerId != null;
    final day = DateTime.parse(_today);
    final dayLabel = '${_weekdays[day.weekday - 1]}, ${day.day} ${_months[day.month - 1]}';

    return Scaffold(
      appBar: AppBar(title: const Text('My work day')),
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
          final inAt = row?.clockInAt?.toLocal();
          final outAt = row?.clockOutAt?.toLocal();

          // Hero: what today looks like so far.
          final (String big, String small, String? pill) = inAt == null
              ? ('Not clocked in', 'Clock in when you start work.', null)
              : outAt == null
                  ? (_hours(DateTime.now().difference(inAt)), 'working today', 'Clocked in at ${hourMinute(inAt)}')
                  : (_hours(outAt.difference(inAt)), 'worked today', 'Day complete');

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                decoration: BoxDecoration(
                  color: AppTheme.barTint,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    Text(dayLabel,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.mutedText)),
                    const SizedBox(height: 4),
                    Text(big,
                        key: const Key('clock-hero'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 34, fontWeight: FontWeight.w800, color: AppTheme.onAccent)),
                    Text(small, style: const TextStyle(fontSize: 13, color: AppTheme.bodyText)),
                    if (pill != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: outAt == null ? const Color(0xFFE3F4EA) : const Color(0xFFEEEAEB),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(pill,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: outAt == null ? const Color(0xFF2E7D4F) : const Color(0xFF5F5A5C),
                            )),
                      ),
                    ],
                  ],
                ),
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
                    _TimeRow(label: 'Clocked in', time: inAt),
                    const Divider(height: 1, color: AppTheme.hairline),
                    _TimeRow(label: 'Clocked out', time: outAt),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (inAt == null && canClockIn)
                _PrimaryButton(
                  label: 'Clock in',
                  icon: Icons.login,
                  onPressed: _busy ? null : () => _clockIn(row),
                )
              else if (inAt != null && outAt == null)
                _PrimaryButton(
                  label: 'Clock out',
                  icon: Icons.logout,
                  onPressed: _busy ? null : () => _clockOut(row!),
                ),
              // Both set -> no button; the day is locked and the rows above
              // show the recorded times.
              const SizedBox(height: 10),
              const Text(
                'Times are final once recorded. If one is wrong, ask the director.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppTheme.mutedText),
              ),
              FutureBuilder<List<StaffAttendance>>(
                future: _week,
                builder: (context, weekSnap) {
                  final rows = weekSnap.data ?? const <StaffAttendance>[];
                  if (rows.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 22),
                      const Text('THIS WEEK',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.9,
                              color: AppTheme.mutedText)),
                      const SizedBox(height: 4),
                      for (final r in rows) _WeekRow(row: r),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

// "Clocked in      07:30  [lock]" -- a lock once the time is recorded, a
// dash while it isn't.
class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.label, required this.time});

  final String label;
  final DateTime? time;

  @override
  Widget build(BuildContext context) {
    final set = time != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: set ? const Color(0xFF2E7D4F) : const Color(0xFFE6D3D8),
              shape: BoxShape.circle,
            ),
            child: set ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.onAccent)),
          ),
          Text(set ? hourMinute(time!) : '—',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: set ? AppTheme.onAccent : AppTheme.mutedText,
              )),
          if (set) ...[
            const SizedBox(width: 8),
            const Icon(Icons.lock_outline, size: 16, color: AppTheme.mutedText),
          ],
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.icon, required this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // A plain FilledButton (not FilledButton.icon) with an icon+text row, so
    // it stays findable as a FilledButton by its label.
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.onAccent,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// One earlier day: "Mon 20    07:28 – 16:05    8 h 37 min".
class _WeekRow extends StatelessWidget {
  const _WeekRow({required this.row});
  final StaffAttendance row;

  static const _abbr = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final d = DateTime.parse(row.date);
    final inAt = row.clockInAt?.toLocal();
    final outAt = row.clockOutAt?.toLocal();
    final times = inAt == null
        ? 'No clock-in'
        : '${hourMinute(inAt)} – ${outAt == null ? '?' : hourMinute(outAt)}';
    final total = inAt != null && outAt != null
        ? _StaffAttendanceScreenState._hours(outAt.difference(inAt))
        : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Text('${_abbr[d.weekday - 1]} ${d.day}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.onAccent)),
          ),
          Text(times, style: const TextStyle(fontSize: 13, color: AppTheme.bodyText)),
          SizedBox(
            width: 84,
            child: Text(total,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.mutedText)),
          ),
        ],
      ),
    );
  }
}
