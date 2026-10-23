import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/child.dart';
import '../../../core/models/class_group.dart';
import '../../../core/models/staff_attendance.dart';
import '../../../core/controllers/attendance_controller.dart';
import '../../../core/controllers/child_controller.dart';
import '../../../core/controllers/class_controller.dart';
import '../../../core/controllers/profile_controller.dart';
import '../../../core/controllers/staff_attendance_controller.dart';
import '../../../core/controllers/teacher_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/util/date_display.dart';
import '../../../shared/widgets/app_loader.dart';
import '../../../shared/widgets/attendance_day_details.dart';
import '../../../shared/widgets/attendance_status_chip.dart';
import '../../../shared/widgets/refreshable_message.dart';
import '../../../shared/widgets/signed_avatar.dart';
import '../../teacher/widgets/attendance_grid_tile.dart';
import '../widgets/staff_attendance_fix_sheet.dart';

// The director's Attendance tab, screen design AA4 (Figma "Screen designs",
// spec 2026-10-23-attendance-redesign-design.md): everyone in the centre for
// one day.
//
// - Children: counts, a banner naming teachers who haven't clocked in, class
//   chips, then one section per class ("BUNGA · 8 OF 14 HERE"). Read-only --
//   tapping a child opens their day (status, photos, note); only teachers
//   mark children.
// - Teachers: each teacher's clock times and status; tapping one opens the
//   fix sheet (status, note, record a missing time).
class DirectorAttendanceScreen extends ConsumerStatefulWidget {
  const DirectorAttendanceScreen({super.key});

  @override
  ConsumerState<DirectorAttendanceScreen> createState() => _DirectorAttendanceScreenState();
}

class _RosterData {
  const _RosterData({
    required this.children,
    required this.attendanceByChild,
    required this.classes,
    required this.teachers,
    required this.staffById,
  });
  final List<Child> children;
  final Map<String, Attendance> attendanceByChild;
  final List<ClassGroup> classes;
  final List<AppUser> teachers;
  final Map<String, StaffAttendance> staffById;

  _RosterData withStaff(StaffAttendance row) => _RosterData(
        children: children,
        attendanceByChild: attendanceByChild,
        classes: classes,
        teachers: teachers,
        staffById: {...staffById, row.staffId: row},
      );
}

class _DirectorAttendanceScreenState extends ConsumerState<DirectorAttendanceScreen> {
  DateTime _selectedDate = DateTime.now();
  String? _classFilter; // null = all classes
  bool _teachersView = false;
  late Future<_RosterData> _future;

  String get _dateString => _selectedDate.toIso8601String().substring(0, 10);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_RosterData> _load() async {
    final date = _dateString;
    // Independent reads, so fetch them together.
    final (children, records, classes, teachers, staffRows) = await (
      ref.read(childControllerProvider).fetchAll(),
      ref.read(attendanceControllerProvider).fetchForDate(date),
      ref.read(classControllerProvider).fetchAll(),
      ref.read(teacherControllerProvider).fetchAll(),
      ref.read(staffAttendanceControllerProvider).fetchForDate(date),
    ).wait;
    return _RosterData(
      children: children,
      attendanceByChild: {for (final r in records) r.childId: r},
      classes: classes,
      teachers: teachers,
      staffById: {for (final r in staffRows) r.staffId: r},
    );
  }

  // Pull-to-refresh. Tab pages are kept alive (LazyIndexedStack), so this is
  // how the director sees attendance marked since the tab opened.
  Future<void> _pullRefresh() async {
    final next = _load();
    setState(() {
      _future = next;
    });
    await next;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      _selectedDate = picked;
      _future = _load();
    });
  }

  Future<void> _applyStaff(StaffAttendance row) async {
    final data = await _future;
    if (!mounted) return;
    setState(() {
      _future = Future.value(data.withStaff(row));
    });
  }

  // A teacher who should be in but has no clock-in for the day. Absent /
  // excused teachers are accounted for, so they don't count as missing.
  static bool _missing(StaffAttendance? row) =>
      row == null ||
      (row.clockInAt == null &&
          row.status != AttendanceStatus.absent &&
          row.status != AttendanceStatus.excused);

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _pullRefresh,
      child: FutureBuilder<_RosterData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return RefreshableMessage('Could not load attendance:\n${snapshot.error}');
          }
          if (!snapshot.hasData) {
            return const Center(child: AppLoader());
          }
          final data = snapshot.data!;
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                sliver: SliverList.list(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(longDayLabel(_selectedDate),
                                  style: const TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.mutedText)),
                              const Text('Attendance',
                                  style: TextStyle(
                                      fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.onAccent)),
                            ],
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Change date',
                          onPressed: _pickDate,
                          style: IconButton.styleFrom(
                            backgroundColor: AppTheme.barTint,
                            foregroundColor: AppTheme.onAccent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.calendar_month_outlined, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _Switch(
                      teachers: _teachersView,
                      onChanged: (v) => setState(() => _teachersView = v),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              ...(_teachersView ? _teacherSlivers(data) : _childSlivers(data)),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }

  // ---------- Children ----------
  List<Widget> _childSlivers(_RosterData data) {
    if (data.children.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No children enrolled yet.'))),
        ),
      ];
    }
    final inScope = _classFilter == null
        ? data.children
        : data.children.where((c) => c.classId == _classFilter).toList();
    var here = 0, waiting = 0, away = 0;
    for (final c in inScope) {
      switch (data.attendanceByChild[c.id]?.status) {
        case null:
          waiting++;
        case AttendanceStatus.present || AttendanceStatus.late:
          here++;
        default:
          away++;
      }
    }
    final missing = data.teachers.where((t) => _missing(data.staffById[t.id])).toList();

    // One section per class (in class order), then children with no class.
    final sections = <(String, List<Child>)>[];
    for (final cls in data.classes) {
      if (_classFilter != null && cls.id != _classFilter) continue;
      final kids = data.children.where((c) => c.classId == cls.id).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (kids.isNotEmpty) sections.add((cls.name, kids));
    }
    if (_classFilter == null) {
      final known = data.classes.map((c) => c.id).toSet();
      final loose = data.children.where((c) => c.classId == null || !known.contains(c.classId)).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (loose.isNotEmpty) sections.add(('No class', loose));
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.list(
          children: [
            Row(
              children: [
                Expanded(child: _Count(key: const Key('count-here'), n: here, label: 'here', color: const Color(0xFF2E7D4F))),
                const SizedBox(width: 8),
                Expanded(child: _Count(key: const Key('count-waiting'), n: waiting, label: 'not in yet', color: const Color(0xFF8A5300))),
                const SizedBox(width: 8),
                Expanded(child: _Count(key: const Key('count-absent'), n: away, label: 'absent', color: const Color(0xFFB3261E))),
              ],
            ),
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 12),
              Material(
                key: const Key('missing-teachers'),
                color: const Color(0xFFFDE7E4),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => setState(() => _teachersView = true),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.person_off_outlined, size: 18, color: Color(0xFFB3261E)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            missing.length == 1
                                ? "${missing.first.name} hasn't clocked in"
                                : "${missing.length} teachers haven't clocked in",
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFB3261E)),
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 18, color: Color(0xFFB3261E)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _Chip(label: 'All', selected: _classFilter == null, onTap: () => setState(() => _classFilter = null)),
                  for (final c in data.classes)
                    _Chip(label: c.name, selected: _classFilter == c.id, onTap: () => setState(() => _classFilter = c.id)),
                ],
              ),
            ),
          ],
        ),
      ),
      if (sections.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No children in this class.'))),
        ),
      for (final (name, kids) in sections) ...[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
          sliver: SliverToBoxAdapter(
            child: _SectionLabel(
              '${name.toUpperCase()} · ${kids.where((k) => _isHere(data.attendanceByChild[k.id])).length} OF ${kids.length} HERE',
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              crossAxisSpacing: 10,
              mainAxisSpacing: 12,
              childAspectRatio: 0.6,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final child = kids[i];
                final record = data.attendanceByChild[child.id];
                return AttendanceGridTile(
                  child: child,
                  attendance: record,
                  readOnly: true,
                  onTap: () => showAttendanceDaySheet(context, child: child, record: record),
                );
              },
              childCount: kids.length,
            ),
          ),
        ),
      ],
    ];
  }

  static bool _isHere(Attendance? r) =>
      r != null && (r.status == AttendanceStatus.present || r.status == AttendanceStatus.late);

  // ---------- Teachers ----------
  List<Widget> _teacherSlivers(_RosterData data) {
    if (data.teachers.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No teachers yet.'))),
        ),
      ];
    }
    final inCount = data.teachers.where((t) => data.staffById[t.id]?.clockInAt != null).length;
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        sliver: SliverToBoxAdapter(
          child: _SectionLabel('TEACHERS · $inCount OF ${data.teachers.length} CLOCKED IN'),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.separated(
          itemCount: data.teachers.length,
          separatorBuilder: (_, _) => const Divider(height: 1, color: AppTheme.hairline),
          itemBuilder: (context, i) {
            final t = data.teachers[i];
            final row = data.staffById[t.id];
            return _TeacherRow(
              teacher: t,
              row: row,
              onTap: () => showStaffAttendanceFixSheet(
                context,
                teacher: t,
                date: _dateString,
                dateLabel: longDayLabel(_selectedDate),
                existing: row,
                onSaved: _applyStaff,
              ),
            );
          },
        ),
      ),
    ];
  }
}

class _TeacherRow extends StatelessWidget {
  const _TeacherRow({required this.teacher, required this.row, required this.onTap});

  final AppUser teacher;
  final StaffAttendance? row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = row;
    final inAt = r?.clockInAt, outAt = r?.clockOutAt;
    final times = inAt == null
        ? 'Not clocked in'
        : 'In ${formatClock(inAt)} · Out ${outAt == null ? '—' : formatClock(outAt)}';
    // The chip says the one thing that matters most for the row.
    final Widget chip;
    if (r != null && (r.status == AttendanceStatus.absent || r.status == AttendanceStatus.excused)) {
      chip = AttendanceStatusChip(status: r.status);
    } else if (inAt == null) {
      chip = const AttendanceStatusChip(status: AttendanceStatus.absent, label: 'Not in');
    } else if (outAt == null) {
      chip = AttendanceStatusChip(
          status: r!.status == AttendanceStatus.late ? AttendanceStatus.late : AttendanceStatus.present,
          label: r.status == AttendanceStatus.late ? 'Late · working' : 'Working');
    } else {
      chip = const _GreyPill('Done');
    }
    return InkWell(
      key: Key('teacher-row-${teacher.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SignedAvatar(
              urlProvider: teacher.avatarPath == null ? null : signedAvatarUrlProvider(teacher.avatarPath!),
              radius: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(teacher.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.onAccent)),
                  Text(times, style: const TextStyle(fontSize: 12, color: AppTheme.mutedText)),
                ],
              ),
            ),
            chip,
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: AppTheme.mutedText),
          ],
        ),
      ),
    );
  }
}

class _GreyPill extends StatelessWidget {
  const _GreyPill(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
        decoration: BoxDecoration(color: const Color(0xFFEEEAEB), borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF5F5A5C))),
      );
}

// Children | Teachers.
class _Switch extends StatelessWidget {
  const _Switch({required this.teachers, required this.onChanged});
  final bool teachers;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool isTeachers) {
      final on = teachers == isTeachers;
      return Expanded(
        child: GestureDetector(
          key: Key('view-${isTeachers ? 'teachers' : 'children'}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(isTeachers),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                  color: on ? AppTheme.onAccent : AppTheme.mutedText,
                )),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.barTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Row(children: [seg('Children', false), seg('Teachers', true)]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? AppTheme.onAccent : Colors.white,
        shape: StadiumBorder(side: BorderSide(color: selected ? AppTheme.onAccent : AppTheme.hairline)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppTheme.onAccent,
                )),
          ),
        ),
      ),
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
