import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'signed_avatar.dart';
import 'app_loader.dart';

// A round avatar (SignedAvatar) that, when tapped, opens a full-screen
// zoomable preview of the photo -- the "tap your profile picture to enlarge"
// gesture familiar from social apps. Tapping a photoless avatar does nothing.
class AvatarWithPreview extends StatelessWidget {
  const AvatarWithPreview({super.key, required this.urlProvider, this.radius = 56});

  // The signed-URL provider for whichever bucket this avatar lives in, or
  // null when no photo is set (then there's nothing to enlarge).
  final ProviderListenable<AsyncValue<String>>? urlProvider;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final provider = urlProvider;
    final avatar = SignedAvatar(urlProvider: provider, radius: radius);
    if (provider == null) return avatar;
    return GestureDetector(
      onTap: () => showDialog<void>(
        context: context,
        // Dim the app behind the photo, like a lightbox.
        barrierColor: Colors.black87,
        builder: (_) => _AvatarPreviewDialog(urlProvider: provider),
      ),
      child: avatar,
    );
  }
}

class _AvatarPreviewDialog extends ConsumerWidget {
  const _AvatarPreviewDialog({required this.urlProvider});

  final ProviderListenable<AsyncValue<String>> urlProvider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: GestureDetector(
        // Tap anywhere to dismiss.
        onTap: () => Navigator.of(context).pop(),
        child: ref.watch(urlProvider).when(
              loading: () => const Center(child: AppLoader()),
              error: (_, _) => const Icon(Icons.broken_image_outlined,
                  size: 64, color: Colors.white70),
              // InteractiveViewer gives pinch-to-zoom / drag on the photo.
              data: (url) => InteractiveViewer(
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
      ),
    );
  }
}
