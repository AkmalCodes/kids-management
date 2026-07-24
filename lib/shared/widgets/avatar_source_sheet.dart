import 'package:flutter/material.dart';

enum AvatarSource { camera, gallery }

// Shared "Take photo / Choose from gallery" bottom sheet used by every
// avatar-editing screen (profile, person detail, child detail). Returns
// null if dismissed.
Future<AvatarSource?> showAvatarSourceSheet(BuildContext context) {
  return showModalBottomSheet<AvatarSource>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Take photo'),
            onTap: () => Navigator.of(sheetContext).pop(AvatarSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.of(sheetContext).pop(AvatarSource.gallery),
          ),
        ],
      ),
    ),
  );
}
