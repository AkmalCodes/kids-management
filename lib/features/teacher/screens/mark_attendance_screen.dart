import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/child.dart';
import '../../../core/models/staff_attendance.dart';
import '../../../core/controllers/attendance_controller.dart';
import '../../../core/controllers/child_controller.dart';
import '../../../core/controllers/photo_capture_controller.dart';
import '../../../core/controllers/staff_attendance_controller.dart';
import '../../../core/controllers/teacher_controller.dart';
import '../../../shared/widgets/app_loader.dart';
import '../widgets/attendance_check_in_sheet.dart';
import '../widgets/attendance_grid_tile.dart';
import '../widgets/staff_grid_tile.dart';
import '../../profile/staff_attendance_screen.dart';
import '../../profile/person_detail_screen.dart';

// The teacher's Attendance tab, screen design AA1 "Arrival board" (Figma
// "Screen designs", spec 2026-10-23-attendance-redesign-design.md).
//
// Children trickle in over the morning and nearly every one gets a check-in
// photo, so the screen is built around "who is still to come":
//
//   Thursday, 23 Oct / Class Bunga        [search]
//   [8 here] [6 waiting] [0 absent]
//   TEACHERS  (own tile -> clock in/out, co-teachers -> profile)
//   WAITING · 6               Mark the rest…   <- tap: camera, then sheet
//   HERE · 8                                  <- tap: same sheet, pre-filled
//   ABSENT · 0  (only when someone is)
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

  // Pull-to-refresh. Tab pages are kept alive (LazyIndexedStack), so this is
  // how the teacher picks up changes made elsewhere (a child enrolled, a
  // colleague clocking in). RefreshIndicator needs a Future to know when to
  // hide its spinner.
  Future<void> _pullRefresh() async {
    final next = _load();
    setState(() {
      _future = next;
    });
    await next;
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
    // All four fetches only need user.id, so run them concurrently. A record
    // of futures `.wait` keeps each result's own type.
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
  // instead of re-fetching everything from the network.
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

  // Tap on a child. Waiting (no record yet): the camera opens first, because
  // the check-in photo is part of arriving; cancelling the camera still opens
  // the sheet so a child can be checked in without one. Already marked: the
  // sheet opens pre-filled.
  Future<void> _openChild(Child child, Attendance? existing) async {
    XFile? photo;
    if (existing == null) {
      try {
        photo = await ref.read(photoCaptureControllerProvider).captureFromCamera();
      } catch (_) {
        photo = null; // no camera (or permission refused): carry on without
      }
      if (!mounted) return;
    }
    await showAttendanceCheckInSheet(
      context,
      child: child,
      date: _today,
      existing: existing,
      newPhoto: photo,
      // Every saved step lands on the grid immediately, even if a later
      // step (a photo upload) fails and the sheet stays open.
      onSaved: (updated) => _applyUpdate(child.id, updated),
    );
  }

  // "Mark the rest…": once arrivals are over, everyone still waiting is
  // marked absent in one go, after a confirm that names them.
  Future<void> _markRestAbsent(List<Child> waiting) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null || waiting.isEmpty) return;
    final names = waiting.map((c) => c.name).join(', ');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Mark ${waiting.length} absent?'),
        content: Text("$names haven't been checked in. They'll be marked absent for today."),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Mark absent'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final service = ref.read(attendanceControllerProvider);
    try {
      // These children have no row yet (that's what "waiting" means), so
      // every call is an insert.
      final saved = await Future.wait([
        for (final c in waiting)
          service.markAttendance(
            childId: c.id,
            centerId: c.centerId,
            date: _today,
            status: AttendanceStatus.absent,
            actorUid: user.id,
          ),
      ]);
      for (final r in saved) {
        await _applyUpdate(r.childId, r);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not mark them absent: $e')));
      // Some may have saved before the failure: show the real state.
      await _pullRefresh();
    }
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

  static const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String get _dateLabel =>
      '${_weekdays[_todayDate.weekday - 1]}, ${_todayDate.day} ${_months[_todayDate.month - 1]}';

  // "Class Bunga" when all of the teacher's children share one class,
  // otherwise a neutral title.
  static String _title(List<Child> children) {
    final names = children.map((c) => c.className.trim()).where((n) => n.isNotEmpty).toSet();
    return names.length == 1 ? names.first : 'Your children';
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _pullRefresh,
      child: FutureBuilder<_RosterData>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: AppLoader());
          }
          final data = snapshot.data!;
          final q = _query.trim().toLowerCase();
          final shown = data.children.where((c) => c.name.toLowerCase().contains(q)).toList();

          // Group by today's state. Counts use the whole class, not the
          // search results, so searching never makes the numbers jump.
          final waiting = <Child>[], here = <Child>[], away = <Child>[];
          for (final c in shown) {
            switch (data.attendanceByChild[c.id]?.status) {
              case null:
                waiting.add(c);
              case AttendanceStatus.present || AttendanceStatus.late:
                here.add(c);
              case AttendanceStatus.absent || AttendanceStatus.excused:
                away.add(c);
            }
          }
          var hereCount = 0, waitingCount = 0, awayCount = 0;
          for (final c in data.children) {
            switch (data.attendanceByChild[c.id]?.status) {
              case null:
                waitingCount++;
              case AttendanceStatus.present || AttendanceStatus.late:
                hereCount++;
              default:
                awayCount++;
            }
          }
          // Arrivals in the order they came in.
          int byArrival(Child a, Child b) => data.attendanceByChild[a.id]!.createdAt
              .compareTo(data.attendanceByChild[b.id]!.createdAt);
          here.sort(byArrival);

          final me = data.teachers.isEmpty ? null : data.teachers.first;

          return CustomScrollView(
            // Scrollable even when short, so it can be pulled to refresh.
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                sliver: SliverList.list(
                  children: [
                    _Header(
                      date: _dateLabel,
                      title: _title(data.children),
                      searching: _searching,
                      controller: _searchController,
                      onQuery: (v) => setState(() => _query = v),
                      onToggleSearch: _toggleSearch,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(child: _Count(key: const Key('count-here'), n: hereCount, label: 'here', color: const Color(0xFF2E7D4F))),
                        const SizedBox(width: 8),
                        Expanded(child: _Count(key: const Key('count-waiting'), n: waitingCount, label: 'waiting', color: const Color(0xFF8A5300))),
                        const SizedBox(width: 8),
                        Expanded(child: _Count(key: const Key('count-absent'), n: awayCount, label: 'absent', color: const Color(0xFFB3261E))),
                      ],
                    ),
                    if (me != null) ...[
                      const SizedBox(height: 16),
                      const _SectionLabel('TEACHERS'),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 92,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: data.teachers.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (context, i) {
                            final t = data.teachers[i];
                            return SizedBox(
                              width: 64,
                              child: StaffGridTile(
                                teacher: t,
                                clockState: t.id == me.id ? data.myClockState : null,
                                onTap: () => _openTeacher(me, t),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Divider(height: 1, color: AppTheme.hairline),
                  ],
                ),
              ),
              if (data.children.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No children assigned to you yet.')),
                  ),
                )
              else if (shown.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text('No students match "$_query".')),
                  ),
                )
              else ...[
                if (waiting.isNotEmpty) ...[
                  _sectionHeader(
                    'WAITING · ${waiting.length}',
                    action: TextButton(
                      onPressed: () => _markRestAbsent(waiting),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.accentPink,
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      child: const Text('Mark the rest…'),
                    ),
                  ),
                  _grid(waiting, data),
                ],
                if (here.isNotEmpty) ...[_sectionHeader('HERE · ${here.length}'), _grid(here, data)],
                if (away.isNotEmpty) ...[_sectionHeader('ABSENT · ${away.length}'), _grid(away, data)],
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeader(String text, {Widget? action}) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
        sliver: SliverToBoxAdapter(
          child: SizedBox(
            height: 32,
            child: Row(children: [Expanded(child: _SectionLabel(text)), ?action]),
          ),
        ),
      );

  Widget _grid(List<Child> children, _RosterData data) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 12,
            mainAxisSpacing: 14,
            // Avatar + name + caption line beneath it.
            childAspectRatio: 0.64,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final child = children[i];
              final existing = data.attendanceByChild[child.id];
              return AttendanceGridTile(
                child: child,
                attendance: existing,
                onTap: () => _openChild(child, existing),
              );
            },
            childCount: children.length,
          ),
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.date,
    required this.title,
    required this.searching,
    required this.controller,
    required this.onQuery,
    required this.onToggleSearch,
  });

  final String date;
  final String title;
  final bool searching;
  final TextEditingController controller;
  final ValueChanged<String> onQuery;
  final VoidCallback onToggleSearch;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: searching
              ? TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Search students…',
                    border: InputBorder.none,
                  ),
                  onChanged: onQuery,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(date,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.mutedText)),
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.onAccent)),
                  ],
                ),
        ),
        IconButton.filledTonal(
          tooltip: searching ? 'Close search' : 'Search students',
          onPressed: onToggleSearch,
          style: IconButton.styleFrom(
            backgroundColor: AppTheme.barTint,
            foregroundColor: AppTheme.onAccent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: Icon(searching ? Icons.close : Icons.search, size: 20),
        ),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({super.key, required this.n, required this.label, required this.color});
  final int n;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppTheme.barTint, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$n', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          Text(label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.mutedText)),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.9, color: AppTheme.mutedText));
}
