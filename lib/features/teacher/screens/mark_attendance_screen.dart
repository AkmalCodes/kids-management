import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/child.dart';
import '../../../core/controllers/attendance_controller.dart';
import '../../../core/controllers/child_controller.dart';
import '../../../core/controllers/photo_capture_controller.dart';
import '../../../shared/widgets/attendance_status_chip.dart';
import '../../../shared/widgets/signed_avatar.dart';
import '../../../shared/widgets/signed_photo_thumbnail.dart';
import '../../../shared/widgets/app_loader.dart';

enum _PhotoAction { camera, gallery, delete }

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
  final DateTime _todayDate = DateTime.now();
  late final String _today = _todayDate.toIso8601String().substring(0, 10);

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
    final children = await ref.read(childControllerProvider).fetchForTeacher(user.id);
    final records = await ref.read(attendanceControllerProvider).fetchForDate(_today);
    return _RosterData(
      children: children,
      attendanceByChild: {for (final r in records) r.childId: r},
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
        );
    await _applyUpdate(child.id, updated);
  }

  // Both photo kinds are entirely optional and independent of each other
  // and of status -- this only requires an existing attendance record so
  // there's an id to attach the photo to (the slot's tap target is
  // disabled until then).
  Future<void> _pickAndSavePhoto(
    Child child,
    Attendance existing, {
    required bool isBelongings,
    required bool fromGallery,
  }) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;
    final captureService = ref.read(photoCaptureControllerProvider);
    final photo = fromGallery
        ? await captureService.pickFromGallery()
        : await captureService.captureFromCamera();
    if (photo == null) return;
    final service = ref.read(attendanceControllerProvider);
    try {
      final Attendance updated;
      if (isBelongings) {
        final path = await service.uploadBelongingsPhoto(
          childId: child.id,
          date: _today,
          photo: photo,
        );
        updated = await service.attachBelongingsPhoto(
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
        updated = await service.attachCheckInPhoto(
          id: existing.id,
          photoPath: path,
          actorUid: user.id,
        );
      }
      await _applyUpdate(child.id, updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save photo: $e')),
      );
    }
  }

  Future<void> _deletePhoto(
    Child child,
    Attendance existing, {
    required bool isBelongings,
  }) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;
    final service = ref.read(attendanceControllerProvider);
    try {
      final updated = isBelongings
          ? await service.removeBelongingsPhoto(
              id: existing.id,
              belongingsPhotoPath: existing.belongingsPhotoPath!,
              actorUid: user.id,
            )
          : await service.removeCheckInPhoto(
              id: existing.id,
              photoPath: existing.photoPath!,
              actorUid: user.id,
            );
      await _applyUpdate(child.id, updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete photo: $e')),
      );
    }
  }

  // Offers take/retake, choose from gallery, and (only once a photo
  // exists) delete -- one entry point covers both the "nothing yet" and
  // "already have one" states.
  Future<void> _showPhotoOptions(
    Child child,
    Attendance existing, {
    required bool isBelongings,
    required bool hasPhoto,
  }) async {
    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text(hasPhoto ? 'Retake photo' : 'Take photo'),
              onTap: () => Navigator.of(sheetContext).pop(_PhotoAction.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(sheetContext).pop(_PhotoAction.gallery),
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete photo'),
                onTap: () => Navigator.of(sheetContext).pop(_PhotoAction.delete),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _PhotoAction.camera:
        await _pickAndSavePhoto(child, existing, isBelongings: isBelongings, fromGallery: false);
      case _PhotoAction.gallery:
        await _pickAndSavePhoto(child, existing, isBelongings: isBelongings, fromGallery: true);
      case _PhotoAction.delete:
        await _deletePhoto(child, existing, isBelongings: isBelongings);
    }
  }

  // Fixed-size regardless of whether it shows the placeholder icon or an
  // existing thumbnail, so the row's total width -- and therefore whether
  // it fits on one line -- never changes depending on photo state.
  static const _photoSlotSize = 36.0;

  Widget _photoSlot({
    required Key key,
    required IconData icon,
    required String? photoPath,
    required VoidCallback? onTap,
  }) {
    final content = photoPath != null
        ? SignedPhotoThumbnail(photoPath: photoPath, radius: _photoSlotSize / 2)
        : Icon(
            icon,
            size: 20,
            color: onTap == null ? Theme.of(context).disabledColor : null,
          );
    return SizedBox(
      key: key,
      width: _photoSlotSize,
      height: _photoSlotSize,
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: content),
      ),
    );
  }

  // Icon/thumbnail + label kept together as one Row so a plain (non-Wrap)
  // Row for both slots never breaks a label away from its own icon. The
  // label is Flexible + ellipsized (not sized to its own intrinsic width)
  // so this fits within whatever width its parent Expanded gives it,
  // instead of forcing the outer Row to overflow on a narrow card.
  Widget _photoSlotWithLabel({
    required Key key,
    required IconData icon,
    required String label,
    required String? photoPath,
    required VoidCallback? onTap,
  }) {
    return Row(
      children: [
        _photoSlot(key: key, icon: icon, photoPath: photoPath, onTap: onTap),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }

  static const _statusChoices = [AttendanceStatus.present, AttendanceStatus.absent];

  String _statusLabel(AttendanceStatus status) => switch (status) {
    AttendanceStatus.present => 'Present',
    AttendanceStatus.absent => 'Absent',
    AttendanceStatus.late => 'Late',
    AttendanceStatus.excused => 'Excused',
  };

  static const _weekdayAbbreviations = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _formatHeaderDate(DateTime date) {
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final yy = (date.year % 100).toString().padLeft(2, '0');
    return '$dd/$mm/$yy ${_weekdayAbbreviations[date.weekday - 1]}';
  }

  // The child's profile picture (from ChildDetailScreen), or a placeholder
  // icon. The day's check-in/belongings photos are separate and shown in
  // the expanded card, not here.
  Widget _avatar(Child child) {
    return SignedAvatar(
      urlProvider:
          child.avatarPath == null ? null : signedChildAvatarUrlProvider(child.avatarPath!),
      radius: 16,
    );
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
                  _avatar(child),
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
                      showCheckmark: false,
                      onSelected: (_) => _setStatus(child, status, existing),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // Plain Row (not Wrap): both slots are a fixed size
              // regardless of photo state (see _photoSlot), and each half
              // is Expanded with an ellipsizing label (see
              // _photoSlotWithLabel), so this always fits on one line no
              // matter how narrow the card is.
              Row(
                children: [
                  Expanded(
                    child: _photoSlotWithLabel(
                      key: Key('checkin-photo-${child.id}'),
                      icon: Icons.camera_alt_outlined,
                      label: 'Check-in photo',
                      photoPath: existing?.photoPath,
                      onTap: existing == null
                          ? null
                          : () => _showPhotoOptions(
                                child,
                                existing,
                                isBelongings: false,
                                hasPhoto: existing.photoPath != null,
                              ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _photoSlotWithLabel(
                      key: Key('belongings-photo-${child.id}'),
                      icon: Icons.checkroom_outlined,
                      label: 'Belongings photo',
                      photoPath: existing?.belongingsPhotoPath,
                      onTap: existing == null
                          ? null
                          : () => _showPhotoOptions(
                                child,
                                existing,
                                isBelongings: true,
                                hasPhoto: existing.belongingsPhotoPath != null,
                              ),
                    ),
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
