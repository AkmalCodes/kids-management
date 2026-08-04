import 'package:flutter/material.dart';

// A bottom-sheet "popout" of row actions, shown when a list row is
// long-pressed (see the onLongPress wiring on the People / Lessons lists).
// Only the actions provided appear -- e.g. a teacher account has no delete
// yet, so it would pass onDelete: null.
Future<void> showRowActionsSheet(
  BuildContext context, {
  required String title,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              dense: true,
              title: Text(
                title,
                style: Theme.of(sheetContext).textTheme.labelMedium,
              ),
            ),
            if (onEdit != null)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onEdit();
                },
              ),
            if (onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onDelete();
                },
              ),
          ],
        ),
      );
    },
  );
}

// Standard confirm dialog for a destructive delete. Returns true if confirmed.
Future<bool> confirmDelete(BuildContext context, {required String message}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Delete?'),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
