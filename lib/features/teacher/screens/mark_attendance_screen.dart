import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/child.dart';
import '../../../core/services/attendance_service.dart';
import '../../../core/services/child_service.dart';
import '../../../core/services/photo_capture_service.dart';
import '../../../shared/widgets/attendance_status_chip.dart';
import '../../../shared/widgets/signed_photo_thumbnail.dart';

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

  bool _searching = false;
  final _searchController = TextEditingController();
  String _query = '';

  // Only one child's card is expanded at a time -- expanding a different
  // one collapses whichever was open, so this holds a single id rather
  // than a set.
  String? _expandedChildId;

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

  void _toggleExpanded(String childId) {
    setState(() {
      _expandedChildId = _expandedChildId == childId ? null : childId;
    });
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

  // Both photo kinds are entirely optional and independent of each other
  // and of status -- this only requires an existing attendance record so
  // there's an id to attach the photo to (the buttons are disabled until
  // then). Once taken, a photo isn't retaken here; that keeps this first
  // version simple.
  Future<void> _capturePhoto(
    Child child,
    Attendance existing, {
    required bool isBelongings,
  }) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;
    final photo = await ref.read(photoCaptureServiceProvider).captureFromCamera();
    if (photo == null) return;
    final service = ref.read(attendanceServiceProvider);
    if (isBelongings) {
      final path = await service.uploadBelongingsPhoto(
        childId: child.id,
        date: _today,
        photo: photo,
      );
      await service.attachBelongingsPhoto(
        id: existing.id,
        belongingsPhotoPath: path,
        actorUid: user.id,
      );
    } else {
      final path = await service.uploadCheckInPhoto(
        childId: child.id,
        date: _today,
        photo: photo,
      );
      await service.attachCheckInPhoto(
        id: existing.id,
        photoPath: path,
        actorUid: user.id,
      );
    }
    setState(() {
      _future = _load();
    });
  }

  Widget _photoSlot({
    required Key key,
    required IconData icon,
    required String? photoPath,
    required VoidCallback? onPressed,
  }) {
    if (photoPath != null) {
      return SignedPhotoThumbnail(photoPath: photoPath, radius: 18);
    }
    return IconButton(key: key, icon: Icon(icon), onPressed: onPressed);
  }

  // Icon + label kept together as one Row so Wrap only ever breaks the
  // line between the two photo slots, never between an icon and its own
  // label.
  Widget _photoSlotWithLabel({
    required Key key,
    required IconData icon,
    required String label,
    required String? photoPath,
    required VoidCallback? onPressed,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _photoSlot(key: key, icon: icon, photoPath: photoPath, onPressed: onPressed),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  static const _statusChoices = [
    AttendanceStatus.present,
    AttendanceStatus.absent,
    AttendanceStatus.late,
  ];

  String _statusLabel(AttendanceStatus status) => switch (status) {
    AttendanceStatus.present => 'Present',
    AttendanceStatus.absent => 'Absent',
    AttendanceStatus.late => 'Late',
    AttendanceStatus.excused => 'Excused',
  };

  Widget _avatar(Attendance? existing) {
    // Reuses today's check-in photo (once taken) as a visual identifier --
    // there's no separate profile picture for a child yet, just a
    // placeholder icon until one has been captured for the day.
    if (existing?.photoPath != null) {
      return SignedPhotoThumbnail(photoPath: existing!.photoPath!, radius: 16);
    }
    return const CircleAvatar(radius: 16, child: Icon(Icons.person_outline, size: 18));
  }

  Widget _childCard(BuildContext context, Child child, Attendance? existing) {
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
                  _avatar(existing),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(child.name, style: Theme.of(context).textTheme.titleMedium),
                  ),
                  if (!isExpanded) ...[
                    existing == null
                        ? const Chip(label: Text('Not marked'), side: BorderSide.none)
                        : AttendanceStatusChip(status: existing.status),
                    const SizedBox(width: 4),
                  ],
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
              // Wrap (not SegmentedButton) so status chips flow onto a
              // second line on a narrow card instead of being squeezed
              // down to a width too small for their own label text.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final status in _statusChoices)
                    ChoiceChip(
                      label: Text(_statusLabel(status)),
                      selected: existing?.status == status,
                      onSelected: (_) => _setStatus(child, status, existing),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _photoSlotWithLabel(
                    key: Key('checkin-photo-${child.id}'),
                    icon: Icons.camera_alt_outlined,
                    label: 'Check-in photo',
                    photoPath: existing?.photoPath,
                    onPressed: existing == null
                        ? null
                        : () => _capturePhoto(child, existing, isBelongings: false),
                  ),
                  _photoSlotWithLabel(
                    key: Key('belongings-photo-${child.id}'),
                    icon: Icons.checkroom_outlined,
                    label: 'Belongings photo',
                    photoPath: existing?.belongingsPhotoPath,
                    onPressed: existing == null
                        ? null
                        : () => _capturePhoto(child, existing, isBelongings: true),
                  ),
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
                    : Text(
                        'Attendance',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
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
                return const Center(child: CircularProgressIndicator());
              }
              final data = snapshot.data!;
              if (data.children.isEmpty) {
                return const Center(child: Text('No children assigned to you yet.'));
              }
              final filtered = data.children
                  .where((c) => c.name.toLowerCase().contains(_query.toLowerCase()))
                  .toList();
              if (filtered.isEmpty) {
                return Center(child: Text('No students match "$_query".'));
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final child = filtered[i];
                  final existing = data.attendanceByChild[child.id];
                  return _childCard(context, child, existing);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
