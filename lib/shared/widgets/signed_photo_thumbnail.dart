import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/attendance_service.dart';

// Cached per photoPath for the life of the app (no .autoDispose) so
// collapsing/re-expanding a card, or navigating away and back, reuses the
// same signed URL instead of re-hitting Storage every time -- that also
// lets Flutter's own NetworkImage cache kick in, since the URL string
// stays identical across rebuilds instead of getting a fresh signature
// each time. Signed URLs are minted for 1 hour (see
// AttendanceService.getSignedPhotoUrl); a session open longer than that
// would need this invalidated, but that's not worth the complexity here.
final signedPhotoUrlProvider = FutureProvider.family<String, String>((ref, photoPath) {
  return ref.watch(attendanceServiceProvider).getSignedPhotoUrl(photoPath);
});

// The attendance-photos Storage bucket is private, so a stored path can't
// be rendered directly -- this exchanges it for a signed URL and shows a
// loading/error state around that fetch.
class SignedPhotoThumbnail extends ConsumerWidget {
  const SignedPhotoThumbnail({super.key, required this.photoPath, this.radius = 20});

  final String photoPath;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urlAsync = ref.watch(signedPhotoUrlProvider(photoPath));
    return urlAsync.when(
      loading: () => CircleAvatar(
        radius: radius,
        child: SizedBox(
          width: radius,
          height: radius,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (_, _) => CircleAvatar(radius: radius, child: const Icon(Icons.broken_image_outlined)),
      data: (url) => CircleAvatar(radius: radius, backgroundImage: NetworkImage(url)),
    );
  }
}
