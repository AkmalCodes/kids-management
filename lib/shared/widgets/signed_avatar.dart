import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/profile_service.dart';

// A round profile picture from the private 'avatars' bucket. Given a stored
// path it fetches a signed URL (cached via signedAvatarUrlProvider); given
// null it shows a person placeholder. Shared by the Profile tab and the
// person-detail screen.
class SignedAvatar extends ConsumerWidget {
  const SignedAvatar({super.key, required this.avatarPath, this.radius = 40});

  final String? avatarPath;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (avatarPath == null) {
      return CircleAvatar(radius: radius, child: Icon(Icons.person_outline, size: radius));
    }
    final urlAsync = ref.watch(signedAvatarUrlProvider(avatarPath!));
    return urlAsync.when(
      loading: () => CircleAvatar(
        radius: radius,
        child: SizedBox(
          width: radius / 2,
          height: radius / 2,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (_, _) =>
          CircleAvatar(radius: radius, child: Icon(Icons.broken_image_outlined, size: radius)),
      data: (url) => CircleAvatar(radius: radius, backgroundImage: NetworkImage(url)),
    );
  }
}
