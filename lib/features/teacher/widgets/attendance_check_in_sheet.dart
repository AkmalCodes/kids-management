import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/controllers/attendance_controller.dart';
import '../../../core/controllers/child_controller.dart';
import '../../../core/controllers/photo_capture_controller.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/child.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/signed_avatar.dart';
import '../../../shared/widgets/attendance_status_chip.dart';

// The one place a teacher checks a child in or changes their day (screen
// design AA2, Figma "Screen designs"). It replaced ChildAttendanceDetailScreen.
//
// Opened from the Attendance tab:
// - a WAITING child: the camera opens first and the photo arrives here as
//   `newPhoto` (null if the camera was cancelled -- the photo is optional);
// - a child already marked: `existing` pre-fills everything.
//
// Nothing is written until the teacher taps the button. Saving is a short
// sequence -- mark the status/notes row, then upload + attach each new
// photo -- because a photo can only hang off an existing row. Every step
// that succeeds is reported through onSaved straight away, so if a later
// step fails the grid behind still shows what WAS saved, and the sheet stays
// open with the error so the teacher can retry.
Future<Attendance?> showAttendanceCheckInSheet(
  BuildContext context, {
  required Child child,
  required String date,
  required ValueChanged<Attendance> onSaved,
  Attendance? existing,
  XFile? newPhoto,
}) {
  return showModalBottomSheet<Attendance>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => AttendanceCheckInSheet(
      child: child,
      date: date,
      existing: existing,
      newPhoto: newPhoto,
      onSaved: onSaved,
    ),
  );
}

class AttendanceCheckInSheet extends ConsumerStatefulWidget {
  const AttendanceCheckInSheet({
    super.key,
    required this.child,
    required this.date,
    required this.onSaved,
    this.existing,
    this.newPhoto,
  });

  final Child child;
  final String date;
  final Attendance? existing;
  final XFile? newPhoto;
  final ValueChanged<Attendance> onSaved;

  @override
  ConsumerState<AttendanceCheckInSheet> createState() => _AttendanceCheckInSheetState();
}

class _AttendanceCheckInSheetState extends ConsumerState<AttendanceCheckInSheet> {
  // The row as last saved. Starts as `existing`, and is replaced after each
  // successful write -- so a retry after a failed photo upload UPDATES the
  // row that was just created instead of trying to insert a second one.
  late Attendance? _record = widget.existing;
  late AttendanceStatus _status = widget.existing?.status ?? AttendanceStatus.present;
  late final TextEditingController _notes =
      TextEditingController(text: widget.existing?.notes ?? '');
  late bool _showNote = (widget.existing?.notes ?? '').trim().isNotEmpty;

  // Photos chosen in this sheet but not uploaded yet, and saved photos the
  // teacher asked to remove. Applied on Save, never before.
  late XFile? _newCheckIn = widget.newPhoto;
  XFile? _newBelongings;
  bool _removeCheckIn = false;
  bool _removeBelongings = false;

  bool _saving = false;
  String? _error;

  bool get _isNew => _record == null;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<XFile?> _pick({required bool camera}) async {
    final capture = ref.read(photoCaptureControllerProvider);
    try {
      return camera ? await capture.captureFromCamera() : await capture.pickFromGallery();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open the camera: $e');
      return null;
    }
  }

  Future<void> _takeCheckIn({required bool camera}) async {
    final photo = await _pick(camera: camera);
    if (photo == null || !mounted) return;
    setState(() {
      _newCheckIn = photo;
      _removeCheckIn = false;
    });
  }

  Future<void> _takeBelongings({required bool camera}) async {
    final photo = await _pick(camera: camera);
    if (photo == null || !mounted) return;
    setState(() {
      _newBelongings = photo;
      _removeBelongings = false;
    });
  }

  void _report(Attendance saved) {
    _record = saved;
    widget.onSaved(saved);
  }

  Future<void> _save() async {
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;
    final service = ref.read(attendanceControllerProvider);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      _report(await service.markAttendance(
        childId: widget.child.id,
        centerId: widget.child.centerId,
        date: widget.date,
        status: _status,
        actorUid: user.id,
        existingId: _record?.id,
        notes: _notes.text.trim(),
      ));

      final checkIn = _newCheckIn;
      if (checkIn != null) {
        final path = await service.uploadCheckInPhoto(
            childId: widget.child.id, date: widget.date, photo: checkIn);
        _report(await service.attachCheckInPhoto(id: _record!.id, photoPath: path, actorUid: user.id));
        _newCheckIn = null;
      } else if (_removeCheckIn && _record!.photoPath != null) {
        _report(await service.removeCheckInPhoto(
            id: _record!.id, photoPath: _record!.photoPath!, actorUid: user.id));
        _removeCheckIn = false;
      }

      final belongings = _newBelongings;
      if (belongings != null) {
        final path = await service.uploadBelongingsPhoto(
            childId: widget.child.id, date: widget.date, photo: belongings);
        _report(await service.attachBelongingsPhoto(
            id: _record!.id, belongingsPhotoPath: path, actorUid: user.id));
        _newBelongings = null;
      } else if (_removeBelongings && _record!.belongingsPhotoPath != null) {
        _report(await service.removeBelongingsPhoto(
            id: _record!.id, belongingsPhotoPath: _record!.belongingsPhotoPath!, actorUid: user.id));
        _removeBelongings = false;
      }

      if (mounted) Navigator.of(context).pop(_record);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not save: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _firstName => widget.child.name.trim().split(RegExp(r'\s+')).first;

  @override
  Widget build(BuildContext context) {
    // Watched (not just read in _save) so the user stream is subscribed
    // before the button can be tapped: a StreamProvider is lazy, and one
    // that is only first read inside a tap handler returns no value yet.
    ref.watch(currentUserProvider);
    final child = widget.child;
    final record = _record;
    final savedCheckIn = _removeCheckIn ? null : record?.photoPath;
    final savedBelongings = _removeBelongings ? null : record?.belongingsPhotoPath;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.fieldBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  SignedAvatar(
                    urlProvider: child.avatarPath == null
                        ? null
                        : signedChildAvatarUrlProvider(child.avatarPath!),
                    radius: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(child.name,
                            style: const TextStyle(
                                fontSize: 19, fontWeight: FontWeight.w800, color: AppTheme.onAccent)),
                        Text(
                          [
                            if (child.className.isNotEmpty) child.className,
                            if (record != null) 'checked in ${formatClock(record.createdAt)}',
                          ].join(' · '),
                          style: const TextStyle(fontSize: 12, color: AppTheme.mutedText),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    color: AppTheme.mutedText,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              // Allergies first: the one thing about a child a teacher must
              // never miss while handling them.
              if (child.allergies.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  key: const Key('allergy-warning'),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDE7E4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFB3261E)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Allergies: ${child.allergies.trim()}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFB3261E))),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              _CheckInPhoto(
                newPhoto: _newCheckIn,
                savedPath: savedCheckIn,
                onCamera: () => _takeCheckIn(camera: true),
                onGallery: () => _takeCheckIn(camera: false),
                onRemove: () => setState(() {
                  _newCheckIn = null;
                  _removeCheckIn = record?.photoPath != null;
                }),
              ),
              const SizedBox(height: 14),
              const _Label('STATUS'),
              const SizedBox(height: 8),
              _StatusPicker(value: _status, onChanged: (s) => setState(() => _status = s)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _BelongingsChip(
                      newPhoto: _newBelongings,
                      savedPath: savedBelongings,
                      onCamera: () => _takeBelongings(camera: true),
                      onGallery: () => _takeBelongings(camera: false),
                      onRemove: () => setState(() {
                        _newBelongings = null;
                        _removeBelongings = record?.belongingsPhotoPath != null;
                      }),
                    ),
                  ),
                  if (!_showNote) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DashedChip(
                        key: const Key('add-note'),
                        icon: Icons.notes_outlined,
                        label: 'Add a note',
                        onTap: () => setState(() => _showNote = true),
                      ),
                    ),
                  ],
                ],
              ),
              if (_showNote) ...[
                const SizedBox(height: 12),
                Theme(
                  data: AppTheme.lightForm(Theme.of(context)),
                  child: TextField(
                    key: const Key('attendance-note'),
                    controller: _notes,
                    minLines: 2,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'Anything the parents should know?'),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(fontSize: 12, color: Color(0xFFB3261E))),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.onAccent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check),
                label: Text(_isNew ? 'Check in $_firstName' : 'Save'),
              ),
            ],
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

// Present / Late / Absent / Excused as one segmented row: every choice
// visible, one tap. Each segment carries its status colour as a dot.
class _StatusPicker extends StatelessWidget {
  const _StatusPicker({required this.value, required this.onChanged});

  final AttendanceStatus value;
  final ValueChanged<AttendanceStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.barTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Row(
        children: [
          for (final s in AttendanceStatus.values)
            Expanded(
              child: GestureDetector(
                key: Key('status-${s.name}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(s),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: s == value ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: s == value
                        ? [
                            BoxShadow(
                              color: AppTheme.onAccent.withValues(alpha: 0.10),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: AttendanceStatusStyle.of(s).foreground,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          AttendanceStatusStyle.of(s).label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: s == value ? FontWeight.w800 : FontWeight.w600,
                            color: s == value ? AppTheme.onAccent : AppTheme.mutedText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// The big check-in photo area: the new (local) photo, else the saved one,
// else an empty slot with camera / gallery buttons.
class _CheckInPhoto extends StatelessWidget {
  const _CheckInPhoto({
    required this.newPhoto,
    required this.savedPath,
    required this.onCamera,
    required this.onGallery,
    required this.onRemove,
  });

  final XFile? newPhoto;
  final String? savedPath;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final has = newPhoto != null || savedPath != null;
    final photo = newPhoto != null
        ? LocalPhoto(newPhoto!)
        : savedPath != null
            ? SignedAttendancePhoto(savedPath!)
            : null;

    return AspectRatio(
      key: const Key('checkin-photo'),
      aspectRatio: 16 / 10,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: ColoredBox(
          color: AppTheme.barTint,
          child: has
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    photo!,
                    Positioned(
                      left: 10,
                      bottom: 10,
                      child: Row(
                        children: [
                          _PhotoPill(icon: Icons.photo_camera_outlined, label: 'Retake', onTap: onCamera),
                          const SizedBox(width: 6),
                          _PhotoPill(icon: Icons.photo_library_outlined, label: 'Gallery', onTap: onGallery),
                          const SizedBox(width: 6),
                          _PhotoPill(icon: Icons.delete_outline, label: 'Remove', onTap: onRemove),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: onCamera,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.onAccent,
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                      ),
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: const Text('Take check-in photo'),
                    ),
                    TextButton(
                      onPressed: onGallery,
                      style: TextButton.styleFrom(foregroundColor: AppTheme.onAccent),
                      child: const Text('Choose from gallery'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _PhotoPill extends StatelessWidget {
  const _PhotoPill({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppTheme.onAccent),
              const SizedBox(width: 4),
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.onAccent)),
            ],
          ),
        ),
      ),
    );
  }
}

// Belongings: a dashed "add" chip, or a small thumbnail with retake/remove.
class _BelongingsChip extends StatelessWidget {
  const _BelongingsChip({
    required this.newPhoto,
    required this.savedPath,
    required this.onCamera,
    required this.onGallery,
    required this.onRemove,
  });

  final XFile? newPhoto;
  final String? savedPath;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    if (newPhoto == null && savedPath == null) {
      return _DashedChip(
        key: const Key('belongings-photo'),
        icon: Icons.backpack_outlined,
        label: 'Belongings photo',
        onTap: onCamera,
        trailing: IconButton(
          tooltip: 'Belongings from gallery',
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          color: AppTheme.mutedText,
          onPressed: onGallery,
          icon: const Icon(Icons.photo_library_outlined),
        ),
      );
    }
    return Container(
      key: const Key('belongings-photo'),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.fieldBorder),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 40,
              height: 40,
              child: newPhoto != null ? LocalPhoto(newPhoto!) : SignedAttendancePhoto(savedPath!),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Belongings',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.onAccent)),
          ),
          IconButton(
            tooltip: 'Retake belongings photo',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: onCamera,
            icon: const Icon(Icons.photo_camera_outlined),
          ),
          IconButton(
            tooltip: 'Remove belongings photo',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class _DashedChip extends StatelessWidget {
  const _DashedChip({super.key, required this.icon, required this.label, required this.onTap, this.trailing});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.fieldBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, trailing == null ? 12 : 2, trailing == null ? 12 : 2, trailing == null ? 12 : 2),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.mutedText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.mutedText)),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

// A photo just taken, shown before it's uploaded. Read as bytes (works on
// every platform, including web, unlike Image.file). Until the bytes arrive
// -- or if they can't be read -- a plain tint stands in; no spinner, so a
// slow read never looks like the app hanging.
class LocalPhoto extends StatefulWidget {
  const LocalPhoto(this.file, {super.key});
  final XFile file;

  @override
  State<LocalPhoto> createState() => _LocalPhotoState();
}

class _LocalPhotoState extends State<LocalPhoto> {
  late Future<Uint8List> _bytes = widget.file.readAsBytes();

  @override
  void didUpdateWidget(covariant LocalPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) _bytes = widget.file.readAsBytes();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snap) => snap.hasData
          ? Image.memory(snap.data!, fit: BoxFit.cover)
          : const ColoredBox(
              color: AppTheme.barTint,
              child: Center(child: Icon(Icons.photo_outlined, color: AppTheme.mutedText)),
            ),
    );
  }
}

// A saved photo from the private attendance-photos bucket, via a signed URL
// (the bucket is private, so the stored path isn't directly viewable).
class SignedAttendancePhoto extends ConsumerStatefulWidget {
  const SignedAttendancePhoto(this.path, {super.key});
  final String path;

  @override
  ConsumerState<SignedAttendancePhoto> createState() => _SignedAttendancePhotoState();
}

class _SignedAttendancePhotoState extends ConsumerState<SignedAttendancePhoto> {
  late Future<String> _url = ref.read(attendanceControllerProvider).getSignedPhotoUrl(widget.path);

  @override
  void didUpdateWidget(covariant SignedAttendancePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _url = ref.read(attendanceControllerProvider).getSignedPhotoUrl(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snap) => snap.hasData
          ? Image.network(
              snap.data!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const ColoredBox(
                color: AppTheme.barTint,
                child: Center(child: Icon(Icons.broken_image_outlined, color: AppTheme.mutedText)),
              ),
            )
          : const ColoredBox(color: AppTheme.barTint),
    );
  }
}
