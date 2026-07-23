import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/child.dart';
import '../../../core/services/attendance_service.dart';
import '../../../core/services/child_service.dart';
import '../../../shared/widgets/attendance_status_chip.dart';
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
      _future = _load();
    });
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
                itemCount: sorted.length,
                itemBuilder: (context, i) {
                  final child = sorted[i];
                  final record = data.attendanceByChild[child.id];
                  return ListTile(
                    leading: record == null ? null : _photoThumbnails(record),
                    title: Text(child.name),
                    trailing: record == null
                        ? const Chip(label: Text('Not marked'), side: BorderSide.none)
                        : AttendanceStatusChip(status: record.status),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // Either or both may be absent since both photos are optional -- only
  // shows a leading widget at all if there's something to show.
  Widget? _photoThumbnails(Attendance record) {
    final thumbnails = [
      if (record.photoPath != null)
        SignedPhotoThumbnail(photoPath: record.photoPath!, radius: 16),
      if (record.belongingsPhotoPath != null)
        SignedPhotoThumbnail(photoPath: record.belongingsPhotoPath!, radius: 16),
    ];
    if (thumbnails.isEmpty) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final thumbnail in thumbnails)
          Padding(padding: const EdgeInsets.only(right: 4), child: thumbnail),
      ],
    );
  }
}
