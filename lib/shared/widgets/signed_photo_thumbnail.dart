import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/attendance_service.dart';

// The attendance-photos Storage bucket is private, so a stored path can't
// be rendered directly — this exchanges it for a signed URL and shows a
// loading/error state around that fetch.
//
// ConsumerStatefulWidget (not a plain ConsumerWidget) so the future is
// computed once in initState and cached — building it fresh inside
// build()'s `future:` on every rebuild would hand FutureBuilder a new
// Future each time and it would never appear to complete.
class SignedPhotoThumbnail extends ConsumerStatefulWidget {
  const SignedPhotoThumbnail({super.key, required this.photoPath, this.radius = 20});

  final String photoPath;
  final double radius;

  @override
  ConsumerState<SignedPhotoThumbnail> createState() => _SignedPhotoThumbnailState();
}

class _SignedPhotoThumbnailState extends ConsumerState<SignedPhotoThumbnail> {
  late Future<String> _urlFuture;

  @override
  void initState() {
    super.initState();
    _urlFuture = _fetchUrl();
  }

  @override
  void didUpdateWidget(SignedPhotoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoPath != widget.photoPath) {
      _urlFuture = _fetchUrl();
    }
  }

  // async (not a plain arrow function) so a synchronous throw from the
  // service call becomes a rejected Future — Dart wraps any throw inside
  // an async function body this way automatically — instead of
  // propagating out of initState and crashing the widget.
  Future<String> _fetchUrl() async {
    return ref.read(attendanceServiceProvider).getSignedPhotoUrl(widget.photoPath);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _urlFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return CircleAvatar(
            radius: widget.radius,
            child: const Icon(Icons.broken_image_outlined),
          );
        }
        if (!snapshot.hasData) {
          return CircleAvatar(
            radius: widget.radius,
            child: SizedBox(
              width: widget.radius,
              height: widget.radius,
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return CircleAvatar(
          radius: widget.radius,
          backgroundImage: NetworkImage(snapshot.data!),
        );
      },
    );
  }
}
