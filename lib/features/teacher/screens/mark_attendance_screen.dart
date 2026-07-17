import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/child.dart';
import '../../../core/services/attendance_service.dart';
import '../../../core/services/child_service.dart';

class MarkAttendanceScreen extends ConsumerStatefulWidget {
  const MarkAttendanceScreen({super.key});

  @override
  ConsumerState<MarkAttendanceScreen> createState() => _MarkAttendanceScreenState();
}

class _RosterData {
  const _RosterData({required this.children, required this.attendanceByChild});
  final List<Child> children;
  final Map<String, Attendance> attendanceByChild;
}

class _MarkAttendanceScreenState extends ConsumerState<MarkAttendanceScreen> {
  late Future<_RosterData> _future;

  // Fixed for the life of the screen so a mark made right before midnight
  // doesn't silently target a different day than what's on screen.
  final String _today = DateTime.now().toIso8601String().substring(0, 10);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_RosterData> _load() async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null) {
      return const _RosterData(children: [], attendanceByChild: {});
    }
    final children = await ref.read(childServiceProvider).fetchForTeacher(user.id);
    final records = await ref.read(attendanceServiceProvider).fetchForDate(_today);
    return _RosterData(
      children: children,
      attendanceByChild: {for (final r in records) r.childId: r},
    );
  }

  Future<void> _setStatus(Child child, AttendanceStatus status, Attendance? existing) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;
    await ref.read(attendanceServiceProvider).markAttendance(
          childId: child.id,
          centerId: child.centerId,
          date: _today,
          status: status,
          actorUid: user.id,
          existingId: existing?.id,
        );
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_RosterData>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        if (data.children.isEmpty) {
          return const Center(child: Text('No children assigned to you yet.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: data.children.length,
          itemBuilder: (context, i) {
            final child = data.children[i];
            final existing = data.attendanceByChild[child.id];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(child.name, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    SegmentedButton<AttendanceStatus>(
                      segments: const [
                        ButtonSegment(
                          value: AttendanceStatus.present,
                          label: Text('Present'),
                        ),
                        ButtonSegment(
                          value: AttendanceStatus.absent,
                          label: Text('Absent'),
                        ),
                        ButtonSegment(value: AttendanceStatus.late, label: Text('Late')),
                        ButtonSegment(
                          value: AttendanceStatus.excused,
                          label: Text('Excused'),
                        ),
                      ],
                      selected: existing == null ? {} : {existing.status},
                      emptySelectionAllowed: true,
                      onSelectionChanged: (selection) {
                        if (selection.isEmpty) return;
                        _setStatus(child, selection.first, existing);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
