import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/child.dart';
import '../../../core/controllers/attendance_controller.dart';
import '../../../core/controllers/child_controller.dart';
import '../../../core/controllers/photo_capture_controller.dart';
import '../../../shared/util/date_display.dart';
import '../../../shared/widgets/signed_avatar.dart';
import '../../../shared/widgets/signed_photo_thumbnail.dart';

enum _PhotoAction { camera, gallery, delete }

// One child's attendance for one day. This holds everything the old
// expand-in-place card on MarkAttendanceScreen held -- status, both photos,
// notes -- at a size where it is actually usable, plus a read-only summary of
// the child.
//
// It owns the writes for this child and reports each saved record back through
// onChanged, so the grid behind it updates without re-fetching the roster.
class ChildAttendanceDetailScreen extends ConsumerStatefulWidget {
  const ChildAttendanceDetailScreen({
    super.key,
    required this.child,
    required this.date,
    required this.initialAttendance,
    required this.onChanged,
  });

  final Child child;
  final String date;
  final Attendance? initialAttendance;
  final ValueChanged<Attendance> onChanged;

  @override
  ConsumerState<ChildAttendanceDetailScreen> createState() =>
      _ChildAttendanceDetailScreenState();
}

class _ChildAttendanceDetailScreenState
    extends ConsumerState<ChildAttendanceDetailScreen> {
  late Attendance? _attendance = widget.initialAttendance;
  late final TextEditingController _notes =
      TextEditingController(text: widget.initialAttendance?.notes ?? '');
  bool _detailsExpanded = false;
  bool _busy = false;

  static const _statusChoices = [AttendanceStatus.present, AttendanceStatus.absent];

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  // Every write funnels through here so the local copy, the parent grid and
  // the notes field never disagree about what was saved.
  //
  // setState is guarded by mounted because a write can still be in flight
  // when the user navigates away -- onChanged still needs to fire so the
  // grid behind this screen gets the saved record, it just must not touch
  // this widget's own state once it is gone.
  void _apply(Attendance updated) {
    if (mounted) {
      setState(() {
        _attendance = updated;
      });
    }
    widget.onChanged(updated);
  }

  Future<void> _setStatus(AttendanceStatus status) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;
    setState(() {
      _busy = true;
    });
    try {
      final updated = await ref.read(attendanceControllerProvider).markAttendance(
            childId: widget.child.id,
            centerId: widget.child.centerId,
            date: widget.date,
            status: status,
            actorUid: user.id,
            existingId: _attendance?.id,
            // Carries forward whatever is currently typed so a status tap
            // never clobbers notes the teacher already entered -- markAttendance
            // writes the notes column unconditionally on every call.
            notes: _notes.text.trim(),
          );
      _apply(updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save attendance: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  // Notes live on the attendance row, so there is nothing to attach them to
  // until a status has been set for the day -- same constraint the photo
  // slots already have (see the Save notes button's enabled condition).
  // Re-sends the current status alongside the typed notes since
  // markAttendance always writes both columns together.
  Future<void> _saveNotes() async {
    final user = ref.read(currentUserProvider).value;
    final current = _attendance;
    if (user == null || current == null) return;
    setState(() => _busy = true);
    try {
      final updated = await ref.read(attendanceControllerProvider).markAttendance(
            childId: widget.child.id,
            centerId: widget.child.centerId,
            date: widget.date,
            status: current.status,
            actorUid: user.id,
            existingId: current.id,
            notes: _notes.text.trim(),
          );
      _apply(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notes saved')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save notes: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = widget.child;
    final current = _attendance;
    // Subscribed here rather than only read inside tap handlers. A
    // StreamProvider is lazy: the first read establishes the subscription and
    // returns AsyncLoading, so a handler that only calls ref.read(...).value
    // sees null and silently does nothing. Watching in build means the
    // subscription is live before anything is tappable, and it does not rely
    // on another screen having warmed the provider first.
    final user = ref.watch(currentUserProvider).value;

    return Scaffold(
      appBar: AppBar(title: Text(child.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _identityStrip(theme, child),
          const Divider(height: 32),
          Text(isoWithWeekday(widget.date), style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Text('Status', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final status in _statusChoices)
                ChoiceChip(
                  label: Text(_statusLabel(status)),
                  selected: current?.status == status,
                  onSelected: (_busy || user == null) ? null : (_) => _setStatus(status),
                ),
            ],
          ),
          const SizedBox(height: 20),
          _photoRow(current, user),
          const SizedBox(height: 20),
          Text('Notes', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'Anything to pass on?'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            // Notes save independently of status, but they live on the
            // attendance row -- disabled until a status exists to hold them,
            // and while any other write on this screen is in flight.
            child: FilledButton(
              onPressed: (_busy || current == null || user == null) ? null : _saveNotes,
              child: const Text('Save notes'),
            ),
          ),
          const Divider(height: 32),
          _childDetails(theme, child),
        ],
      ),
    );
  }

  Widget _identityStrip(ThemeData theme, Child child) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SignedAvatar(
          urlProvider: child.avatarPath == null
              ? null
              : signedChildAvatarUrlProvider(child.avatarPath!),
          radius: 32,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(child.name, style: theme.textTheme.titleLarge),
              if (child.className.isNotEmpty)
                Text(child.className, style: theme.textTheme.bodyMedium),
              // Always visible, never behind the collapse: allergy information
              // can be needed immediately and a teacher should not have to know
              // to go looking for it.
              if (child.allergies.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Chip(
                  key: const Key('allergy-chip'),
                  avatar: const Icon(Icons.warning_amber, size: 18),
                  label: Text(child.allergies),
                  backgroundColor: theme.colorScheme.errorContainer,
                  side: BorderSide.none,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // Read-only on purpose: RLS restricts children writes to directors, so an
  // edit affordance here could only ever produce a failure.
  Widget _childDetails(ThemeData theme, Child child) {
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: const Text('Child details'),
        tilePadding: EdgeInsets.zero,
        initiallyExpanded: _detailsExpanded,
        onExpansionChanged: (v) => setState(() => _detailsExpanded = v),
        children: [
          _detailRow(theme, 'Date of birth', '${_formatDate(child.dob)}  •  Age ${_age(child.dob)}'),
          if (child.className.isNotEmpty) _detailRow(theme, 'Class', child.className),
          if (child.allergies.trim().isNotEmpty)
            _detailRow(theme, 'Allergies', child.allergies),
          if (child.notes.trim().isNotEmpty) _detailRow(theme, 'Notes', child.notes),
        ],
      ),
    );
  }

  Widget _detailRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  // user is passed in from build() (already watched there) rather than
  // read again here -- one subscription to currentUserProvider per build.
  Widget _photoRow(Attendance? current, AppUser? user) {
    return Row(
      children: [
        Expanded(
          child: _photoSlotWithLabel(
            key: const Key('checkin-photo'),
            label: 'Check-in photo',
            photoPath: current?.photoPath,
            onTap: (_busy || current == null || user == null)
                ? null
                : () => _photoMenu(current, isBelongings: false),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _photoSlotWithLabel(
            key: const Key('belongings-photo'),
            label: 'Belongings',
            photoPath: current?.belongingsPhotoPath,
            onTap: (_busy || current == null || user == null)
                ? null
                : () => _photoMenu(current, isBelongings: true),
          ),
        ),
      ],
    );
  }

  Widget _photoSlotWithLabel({
    required Key key,
    required String label,
    required String? photoPath,
    required VoidCallback? onTap,
  }) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 6),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 96,
            child: photoPath == null
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    child: const Center(child: Icon(Icons.add_a_photo_outlined)),
                  )
                : SignedPhotoThumbnail(photoPath: photoPath, radius: 48),
          ),
        ),
      ],
    );
  }

  // A photo can only hang off an existing attendance row, so the slots stay
  // disabled until a status has been set. Both photos are optional and
  // independent of each other and of the status.
  //
  // Saving is two steps by design: upload the file to the private bucket, then
  // write the returned Storage path onto the row. The controller exposes them
  // separately, so a failed attach cannot leave a half-written row pointing at
  // nothing.
  Future<void> _pickAndSavePhoto(
    Attendance record, {
    required bool isBelongings,
    required bool fromGallery,
  }) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;
    final capture = ref.read(photoCaptureControllerProvider);
    final photo = fromGallery
        ? await capture.pickFromGallery()
        : await capture.captureFromCamera();
    if (photo == null) return;

    final service = ref.read(attendanceControllerProvider);
    setState(() => _busy = true);
    try {
      final Attendance updated;
      if (isBelongings) {
        final path = await service.uploadBelongingsPhoto(
          childId: widget.child.id,
          date: widget.date,
          photo: photo,
        );
        updated = await service.attachBelongingsPhoto(
          id: record.id,
          belongingsPhotoPath: path,
          actorUid: user.id,
        );
      } else {
        final path = await service.uploadCheckInPhoto(
          childId: widget.child.id,
          date: widget.date,
          photo: photo,
        );
        updated = await service.attachCheckInPhoto(
          id: record.id,
          photoPath: path,
          actorUid: user.id,
        );
      }
      _apply(updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save photo: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Camera / gallery / delete, matching what the expanded card offered.
  Future<void> _photoMenu(Attendance record, {required bool isBelongings}) async {
    final hasPhoto = isBelongings
        ? record.belongingsPhotoPath != null
        : record.photoPath != null;

    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
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
                title: const Text('Remove photo'),
                onTap: () => Navigator.of(sheetContext).pop(_PhotoAction.delete),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;

    final user = ref.read(currentUserProvider).value;
    if (user == null) return;
    final service = ref.read(attendanceControllerProvider);

    switch (action) {
      case _PhotoAction.camera:
        await _pickAndSavePhoto(record, isBelongings: isBelongings, fromGallery: false);
      case _PhotoAction.gallery:
        await _pickAndSavePhoto(record, isBelongings: isBelongings, fromGallery: true);
      case _PhotoAction.delete:
        setState(() => _busy = true);
        try {
          final updated = isBelongings
              ? await service.removeBelongingsPhoto(
                  id: record.id,
                  belongingsPhotoPath: record.belongingsPhotoPath!,
                  actorUid: user.id,
                )
              : await service.removeCheckInPhoto(
                  id: record.id,
                  photoPath: record.photoPath!,
                  actorUid: user.id,
                );
          _apply(updated);
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not remove photo: $e')),
          );
        } finally {
          if (mounted) setState(() => _busy = false);
        }
    }
  }

  static String _statusLabel(AttendanceStatus status) => switch (status) {
        AttendanceStatus.present => 'Present',
        AttendanceStatus.absent => 'Absent',
        AttendanceStatus.late => 'Late',
        AttendanceStatus.excused => 'Excused',
      };

  static String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static int _age(DateTime dob) {
    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }
}
