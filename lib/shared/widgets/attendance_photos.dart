import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/controllers/attendance_controller.dart';
import '../../core/theme/app_theme.dart';

// Photo widgets shared by the attendance screens of every role: the
// teacher's check-in sheet, the director's read-only day sheet and the
// parent's today card / day detail.

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
