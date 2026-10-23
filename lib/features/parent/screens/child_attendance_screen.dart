import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/child.dart';
import '../../../core/controllers/attendance_controller.dart';
import '../../../core/controllers/child_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/util/date_display.dart';
import '../../../shared/widgets/app_loader.dart';
import '../../../shared/widgets/attendance_photos.dart';
import '../../../shared/widgets/attendance_status_chip.dart';
import '../../../shared/widgets/signed_avatar.dart';
import 'attendance_detail_screen.dart';

// The parent's Attendance tab, screen design AA5 (Figma "Screen designs",
// spec 2026-10-23-attendance-redesign-design.md). Parents open it to check
// one thing -- did my child arrive, and how do they look today? -- so today
// leads:
//
//   [Aisyah] [Adam]              <- only with more than one child
//   ┌ today's check-in photo ┐
//   │ ● Present · 07:52       │
//   │ Aisyah is at school     │
//   THIS WEEK  M ✓ T ✗ W ✓ T ◯ F
//   EARLIER    one card per day -> AttendanceDetailScreen
class ChildAttendanceScreen extends ConsumerStatefulWidget {
  const ChildAttendanceScreen({super.key, this.today});

  // Injectable "today" so widget tests are date-deterministic.
  final DateTime? today;

  @override
  ConsumerState<ChildAttendanceScreen> createState() => _ChildAttendanceScreenState();
}

class _ChildAttendanceScreenState extends ConsumerState<ChildAttendanceScreen> {
  late Future<List<Child>> _children;
  String? _selectedId;
  // One history fetch per child, kept so switching chips back and forth
  // doesn't refetch.
  final Map<String, Future<List<Attendance>>> _history = {};

  DateTime get _today {
    final t = widget.today ?? DateTime.now();
    return DateTime(t.year, t.month, t.day);
  }

  static String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

  @override
  void initState() {
    super.initState();
    _children = _loadChildren();
  }

  Future<List<Child>> _loadChildren() async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return const [];
    return ref.read(childControllerProvider).fetchForParent(user.id);
  }

  Future<List<Attendance>> _historyFor(String childId) =>
      _history[childId] ??= ref.read(attendanceControllerProvider).fetchForChild(childId);

  // Pull-to-refresh: the tab is kept alive, so this is how a parent sees a
  // check-in that happened while the app was open.
  Future<void> _refresh() async {
    _history.clear();
    final next = _loadChildren();
    setState(() {
      _children = next;
    });
    final kids = await next;
    final id = _selectedId ?? (kids.isEmpty ? null : kids.first.id);
    if (id != null) await _historyFor(id);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Child>>(
      future: _children,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Could not load: ${snapshot.error}'));
        }
        if (!snapshot.hasData) return const Center(child: AppLoader());
        final children = snapshot.data!;
        if (children.isEmpty) {
          return const Center(child: Text('No children linked to your account yet.'));
        }
        final child = children.firstWhere((c) => c.id == _selectedId, orElse: () => children.first);

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              if (children.length > 1) ...[
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final c in children)
                        _ChildChip(
                          child: c,
                          selected: c.id == child.id,
                          onTap: () => setState(() => _selectedId = c.id),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              FutureBuilder<List<Attendance>>(
                future: _historyFor(child.id),
                builder: (context, snap) {
                  if (snap.hasError) return Text('Could not load attendance: ${snap.error}');
                  if (!snap.hasData) {
                    return const Padding(padding: EdgeInsets.all(24), child: Center(child: AppLoader()));
                  }
                  return _ChildDays(child: child, records: snap.data!, today: _today, iso: _iso);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChildDays extends StatelessWidget {
  const _ChildDays({required this.child, required this.records, required this.today, required this.iso});

  final Child child;
  final List<Attendance> records;
  final DateTime today;
  final String Function(DateTime) iso;

  String get _firstName => child.name.trim().split(RegExp(r'\s+')).first;

  void _open(BuildContext context, Attendance r) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AttendanceDetailScreen(record: r, childName: child.name)),
      );

  @override
  Widget build(BuildContext context) {
    final byDate = {for (final r in records) r.date: r};
    final todayRec = byDate[iso(today)];
    final monday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
    final week = [for (var i = 0; i < 5; i++) DateTime(monday.year, monday.month, monday.day + i)];
    final earlier = records.where((r) => r.date.compareTo(iso(today)) < 0).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TodayCard(
          firstName: _firstName,
          record: todayRec,
          onTap: todayRec == null ? null : () => _open(context, todayRec),
        ),
        const SizedBox(height: 18),
        const _Label('THIS WEEK'),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final d in week)
              _WeekDot(
                day: d,
                record: byDate[iso(d)],
                isToday: d == today,
                future: d.isAfter(today),
              ),
          ],
        ),
        const SizedBox(height: 18),
        const _Label('EARLIER'),
        const SizedBox(height: 8),
        if (earlier.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No earlier days yet.', style: TextStyle(color: AppTheme.mutedText)),
          )
        else
          for (final r in earlier) _DayCard(record: r, onTap: () => _open(context, r)),
      ],
    );
  }
}

// Today: the photo and one plain sentence.
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.firstName, required this.record, required this.onTap});

  final String firstName;
  final Attendance? record;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final String headline;
    final String? sub;
    if (r == null) {
      headline = 'Not checked in yet';
      sub = "You'll see $firstName's check-in photo here once they arrive.";
    } else {
      switch (r.status) {
        case AttendanceStatus.present || AttendanceStatus.late:
          headline = '$firstName is at school';
          sub = r.notes.trim().isEmpty ? null : 'Note from teacher: ${r.notes.trim()}';
        case AttendanceStatus.absent:
          headline = '$firstName is absent today';
          sub = r.notes.trim().isEmpty ? null : r.notes.trim();
        case AttendanceStatus.excused:
          headline = '$firstName is excused today';
          sub = r.notes.trim().isEmpty ? null : r.notes.trim();
      }
    }
    final arrived = r != null && (r.status == AttendanceStatus.present || r.status == AttendanceStatus.late);

    return Material(
      key: const Key('today-card'),
      color: r == null ? AppTheme.barTint : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: r == null ? Colors.transparent : AppTheme.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (r?.photoPath != null)
              AspectRatio(aspectRatio: 16 / 10, child: SignedAttendancePhoto(r!.photoPath!)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (r != null) ...[
                    AttendanceStatusChip(
                      status: r.status,
                      label: arrived
                          ? '${AttendanceStatusStyle.of(r.status).label} · checked in ${formatClock(r.createdAt)}'
                          : null,
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(headline,
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppTheme.onAccent)),
                  if (sub != null) ...[
                    const SizedBox(height: 4),
                    Text(sub, style: const TextStyle(fontSize: 13, height: 1.35, color: AppTheme.bodyText)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekDot extends StatelessWidget {
  const _WeekDot({required this.day, required this.record, required this.isToday, required this.future});

  final DateTime day;
  final Attendance? record;
  final bool isToday;
  final bool future;

  static const _abbr = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];

  @override
  Widget build(BuildContext context) {
    final r = record;
    return Column(
      key: Key('week-${day.weekday}'),
      children: [
        Text(_abbr[day.weekday - 1],
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isToday ? AppTheme.accentPink : AppTheme.mutedText,
            )),
        const SizedBox(height: 4),
        r != null
            ? AttendanceStatusBadge(status: r.status, size: 28)
            : Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isToday ? AppTheme.accentPink : AppTheme.fieldBorder,
                    width: isToday ? 2 : 1.5,
                  ),
                  color: future ? Colors.transparent : AppTheme.barTint,
                ),
              ),
      ],
    );
  }
}

// One earlier day: thumbnail (or a status tile), date, "07:49 · Present".
class _DayCard extends StatelessWidget {
  const _DayCard({required this.record, required this.onTap});

  final Attendance record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final style = AttendanceStatusStyle.of(r.status);
    final arrived = r.status == AttendanceStatus.present || r.status == AttendanceStatus.late;
    final day = DateTime.tryParse(r.date);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: r.photoPath != null
                        ? SignedAttendancePhoto(r.photoPath!)
                        : ColoredBox(
                            color: style.background,
                            child: Icon(style.icon, size: 20, color: style.foreground),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(day == null ? r.date : longDayLabel(day),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.onAccent)),
                      Text(
                        arrived ? '${formatClock(r.createdAt)} · ${style.label}' : style.label,
                        style: const TextStyle(fontSize: 12, color: AppTheme.mutedText),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppTheme.mutedText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChildChip extends StatelessWidget {
  const _ChildChip({required this.child, required this.selected, required this.onTap});

  final Child child;
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
            padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SignedAvatar(
                  urlProvider: child.avatarPath == null ? null : signedChildAvatarUrlProvider(child.avatarPath!),
                  radius: 14,
                ),
                const SizedBox(width: 8),
                Text(child.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : AppTheme.onAccent,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.9, color: AppTheme.mutedText));
}
