import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/child.dart';
import '../../../core/models/staff_attendance.dart';
import '../../../core/controllers/attendance_controller.dart';
import '../../../core/controllers/child_controller.dart';
import '../../../core/controllers/staff_attendance_controller.dart';
import '../../../core/controllers/teacher_controller.dart';
import '../../../shared/widgets/app_loader.dart';
import '../widgets/attendance_grid_tile.dart';
import '../widgets/staff_grid_tile.dart';
import '../../profile/staff_attendance_screen.dart';
import '../../profile/person_detail_screen.dart';
import 'child_attendance_detail_screen.dart';

class MarkAttendanceScreen extends ConsumerStatefulWidget {
  const MarkAttendanceScreen({super.key});

  @override
  ConsumerState<MarkAttendanceScreen> createState() => _MarkAttendanceScreenState();
}

class _RosterData {
  const _RosterData({
    required this.children,
    required this.attendanceByChild,
    required this.teachers, // signed-in teacher first, then co-teachers by name
    required this.myClockState,
  });
  final List<Child> children;
  final Map<String, Attendance> attendanceByChild;
  final List<AppUser> teachers;
  final StaffClockState myClockState;
}

class _MarkAttendanceScreenState extends ConsumerState<MarkAttendanceScreen> {
  late Future<_RosterData> _future;

  // Fixed for the life of the screen so a mark made right before midnight
  // doesn't silently target a different day than what's on screen.
  final DateTime _todayDate = DateTime.now();
  late final String _today = _todayDate.toIso8601String().substring(0, 10);

  bool _searching = false;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchController.clear();
        _query = '';
      }
    });
  }

  Future<_RosterData> _load() async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null) {
      return const _RosterData(
        children: [],
        attendanceByChild: {},
        teachers: [],
        myClockState: StaffClockState.notClockedIn,
      );
    }
    // All four fetches only need user.id, so run them concurrently rather than
    // awaiting one after another (the design doc's Data-flow section: "in
    // parallel"). Record-of-futures `.wait` keeps each result's own type.
    final (children, records, coTeachers, staffRows) = await (
      ref.read(childControllerProvider).fetchForTeacher(user.id),
      ref.read(attendanceControllerProvider).fetchForDate(_today),
      ref.read(teacherControllerProvider).fetchCoTeachers(user.id),
      ref.read(staffAttendanceControllerProvider).fetchForDate(_today),
    ).wait;

    StaffAttendance? mine;
    for (final r in staffRows) {
      if (r.staffId == user.id) {
        mine = r;
        break;
      }
    }
    final myClockState = mine?.clockOutAt != null
        ? StaffClockState.done
        : mine?.clockInAt != null
            ? StaffClockState.working
            : StaffClockState.notClockedIn;

    return _RosterData(
      children: children,
      attendanceByChild: {for (final r in records) r.childId: r},
      teachers: [user, ...coTeachers],
      myClockState: myClockState,
    );
  }

  // Applies a write's returned row straight to the already-loaded roster
  // instead of re-fetching everything from the network -- that round trip
  // was why status changes visibly lagged before this (same fix already
  // applied to schedule entries; see ScheduleController).
  Future<void> _applyUpdate(String childId, Attendance updated) async {
    final data = await _future;
    if (!mounted) return;
    setState(() {
      _future = Future.value(
        _RosterData(
          children: data.children,
          attendanceByChild: {...data.attendanceByChild, childId: updated},
          teachers: data.teachers,
          myClockState: data.myClockState,
        ),
      );
    });
  }

  Future<void> _setStatus(Child child, AttendanceStatus status, Attendance? existing) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;
    final updated = await ref.read(attendanceControllerProvider).markAttendance(
          childId: child.id,
          centerId: child.centerId,
          date: _today,
          status: status,
          actorUid: user.id,
          existingId: existing?.id,
          // markAttendance writes the notes column unconditionally on every
          // call (default ''), so an update that omits this would silently
          // blank out any note the teacher already saved on this record.
          notes: existing?.notes ?? '',
        );
    await _applyUpdate(child.id, updated);
  }

  Future<void> _openDetail(Child child, Attendance? existing) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChildAttendanceDetailScreen(
          child: child,
          date: _today,
          initialAttendance: existing,
          // The detail screen reports every save back, so the grid behind it
          // is already correct when the user returns -- no re-fetch, no flash
          // of stale badges.
          onChanged: (updated) => _applyUpdate(child.id, updated),
        ),
      ),
    );
  }

  Future<void> _openTeacher(AppUser me, AppUser teacher) async {
    if (teacher.id == me.id) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const StaffAttendanceScreen()),
      );
      // The clock screen has no onChanged callback; re-load so the own-tile
      // badge reflects a clock-in done while it was open.
      if (mounted) {
        setState(() {
          _future = _load();
        });
      }
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PersonDetailScreen(person: teacher, readOnly: true),
        ),
      );
    }
  }

  // Long-press is the shortcut for the common case. Everything reachable here
  // is also reachable by tapping through to the detail screen, so the gesture
  // being undiscoverable costs nothing.
  Future<void> _showActions(Child child, Attendance? existing) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Open details'),
              onTap: () => Navigator.of(sheetContext).pop('details'),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Mark present'),
              onTap: () => Navigator.of(sheetContext).pop('present'),
            ),
            ListTile(
              leading: const Icon(Icons.cancel_outlined),
              title: const Text('Mark absent'),
              onTap: () => Navigator.of(sheetContext).pop('absent'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case 'details':
        await _openDetail(child, existing);
      case 'present':
        await _setStatus(child, AttendanceStatus.present, existing);
      case 'absent':
        await _setStatus(child, AttendanceStatus.absent, existing);
    }
  }

  static const _weekdayAbbreviations = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _formatHeaderDate(DateTime date) {
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final yy = (date.year % 100).toString().padLeft(2, '0');
    return '$dd/$mm/$yy ${_weekdayAbbreviations[date.weekday - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: _searching
                    ? TextField(
                        controller: _searchController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'Search students…',
                          border: InputBorder.none,
                        ),
                        onChanged: (value) => setState(() => _query = value),
                      )
                    : Row(
                        children: [
                          Text(
                            'Attendance',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          // Flexible + ellipsis: on a narrow screen this
                          // shrinks/truncates first rather than forcing
                          // the row to overflow past the search icon.
                          Flexible(
                            child: Text(
                              _formatHeaderDate(_todayDate),
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
              ),
              IconButton(
                icon: Icon(_searching ? Icons.close : Icons.search),
                tooltip: _searching ? 'Close search' : 'Search students',
                onPressed: _toggleSearch,
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<_RosterData>(
            future: _future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: AppLoader());
              }
              final data = snapshot.data!;
              final filteredChildren = data.children
                  .where((c) => c.name.toLowerCase().contains(_query.toLowerCase()))
                  .toList();

              const gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
                // Taller than wide: the tile is a square avatar plus a name
                // line beneath it.
                childAspectRatio: 0.72,
              );

              return CustomScrollView(
                slivers: [
                  const SliverToBoxAdapter(child: _SectionDivider('Teachers')),
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverGrid(
                      gridDelegate: gridDelegate,
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          // This grid only builds when data.teachers is
                          // non-empty, and its first entry is always the
                          // signed-in user (see _load), so `me` is safe here.
                          final me = data.teachers.first;
                          final t = data.teachers[i];
                          return StaffGridTile(
                            teacher: t,
                            clockState: t.id == me.id ? data.myClockState : null,
                            onTap: () => _openTeacher(me, t),
                          );
                        },
                        childCount: data.teachers.length,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: _SectionDivider('Children')),
                  if (data.children.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('No children assigned to you yet.')),
                      ),
                    )
                  else if (filteredChildren.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(child: Text('No students match "$_query".')),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverGrid(
                        gridDelegate: gridDelegate,
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final child = filteredChildren[i];
                            final existing = data.attendanceByChild[child.id];
                            return AttendanceGridTile(
                              child: child,
                              attendance: existing,
                              onTap: () => _openDetail(child, existing),
                              onLongPress: () => _showActions(child, existing),
                            );
                          },
                          childCount: filteredChildren.length,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// A centred, uppercase caption between two rules -- "——— TEACHERS ———". Splits
// the scroll view into its two grids without a heavyweight header.
class _SectionDivider extends StatelessWidget {
  const _SectionDivider(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w600,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(label.toUpperCase(), style: style),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}
