import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// A round avatar backed by a private-bucket signed URL. The caller passes
// the URL provider for the relevant bucket (e.g. signedAvatarUrlProvider
// for users, signedChildAvatarUrlProvider for children), or null to show a
// person placeholder. Kept bucket-agnostic so it's reused everywhere.
class SignedAvatar extends ConsumerWidget {
  const SignedAvatar({super.key, required this.urlProvider, this.radius = 40});

  final ProviderListenable<AsyncValue<String>>? urlProvider;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = urlProvider;
    if (provider == null) {
      return CircleAvatar(radius: radius, child: Icon(Icons.person_outline, size: radius));
    }
    return ref.watch(provider).when(
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
