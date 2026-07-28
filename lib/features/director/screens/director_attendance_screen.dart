import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/child.dart';
import '../../../core/services/attendance_service.dart';
import '../../../core/services/child_service.dart';
import '../../../shared/widgets/attendance_status_chip.dart';
import '../../../shared/widgets/signed_avatar.dart';
import '../../../shared/widgets/signed_photo_thumbnail.dart';

class DirectorAttendanceScreen extends ConsumerStatefulWidget {
  const DirectorAttendanceScreen({super.key});

  @override
  ConsumerState<DirectorAttendanceScreen> createState() => _DirectorAttendanceScreenState();
}

class _RosterData {
  const _RosterData({required this.children, required this.attendanceByChild});
  final List<Child> children;
  final Map<String, Attendance> attendanceByChild;
}

class _DirectorAttendanceScreenState extends ConsumerState<DirectorAttendanceScreen> {
  DateTime _selectedDate = DateTime.now();
  late Future<_RosterData> _future;

  // Only one child's card is expanded at a time (same accordion behaviour
  // as the teacher's attendance screen).
  String? _expandedChildId;

  String get _dateString => _selectedDate.toIso8601String().substring(0, 10);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_RosterData> _load() async {
    final children = await ref.read(childServiceProvider).fetchAll();
    final records = await ref.read(attendanceServiceProvider).fetchForDate(_dateString);
    return _RosterData(
      children: children,
      attendanceByChild: {for (final r in records) r.childId: r},
    );
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
      _expandedChildId = null;
      _future = _load();
    });
  }

  void _toggleExpanded(String childId) {
    setState(() {
      _expandedChildId = _expandedChildId == childId ? null : childId;
    });
  }

  // The child's profile picture (from ChildDetailScreen), or a placeholder
  // icon -- matches the teacher screen. The day's check-in/belongings
  // photos are shown in the expanded card, not here.
  Widget _avatar(Child child) {
    return SignedAvatar(
      urlProvider:
          child.avatarPath == null ? null : signedChildAvatarUrlProvider(child.avatarPath!),
      radius: 16,
    );
  }

  // A read-only photo slot for the expanded view (director doesn't capture
  // photos): a thumbnail if present, or a muted "none" placeholder.
  Widget _photoSlot(String label, String? photoPath) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        photoPath != null
            ? SignedPhotoThumbnail(photoPath: photoPath, radius: 18)
            : CircleAvatar(
                radius: 18,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.image_not_supported_outlined,
                  size: 18,
                  color: Theme.of(context).disabledColor,
                ),
              ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _childCard(BuildContext context, Child child, Attendance? record) {
    final isExpanded = _expandedChildId == child.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => _toggleExpanded(child.id),
              child: Row(
                children: [
                  _avatar(child),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(child.name, style: Theme.of(context).textTheme.titleMedium),
                  ),
                  record == null
                      ? const Chip(label: Text('Not marked'), side: BorderSide.none)
                      : AttendanceStatusChip(status: record.status),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: isExpanded ? -0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.chevron_left),
                  ),
                ],
              ),
            ),
            if (isExpanded) ...[
              const SizedBox(height: 12),
              if (record == null)
                Text(
                  'No attendance recorded for this day.',
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              else
                Row(
                  children: [
                    Expanded(child: _photoSlot('Check-in photo', record.photoPath)),
                    const SizedBox(width: 8),
                    Expanded(child: _photoSlot('Belongings photo', record.belongingsPhotoPath)),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(_dateString, style: Theme.of(context).textTheme.titleMedium),
              ),
              TextButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('Change date'),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<_RosterData>(
            future: _future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snapshot.data!;
              if (data.children.isEmpty) {
                return const Center(child: Text('No children enrolled yet.'));
              }
              final sorted = [...data.children]..sort((a, b) => a.name.compareTo(b.name));
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: sorted.length,
                itemBuilder: (context, i) {
                  final child = sorted[i];
                  return _childCard(context, child, data.attendanceByChild[child.id]);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
