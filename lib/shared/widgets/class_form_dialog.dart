import 'package:flutter/material.dart';
import '../../core/models/app_user.dart';

typedef ClassFormResult = ({String name, String? teacherId});

// Create/edit-a-class dialog: name + a teacher dropdown. Returns null on
// cancel. Shared by ManageClassesScreen's create and edit flows.
Future<ClassFormResult?> showClassFormDialog(
  BuildContext context, {
  required String title,
  required List<AppUser> teachers,
  String initialName = '',
  String? initialTeacherId,
}) {
  return showDialog<ClassFormResult>(
    context: context,
    builder: (_) => _ClassFormDialog(
      title: title,
      teachers: teachers,
      initialName: initialName,
      initialTeacherId: initialTeacherId,
    ),
  );
}

class _ClassFormDialog extends StatefulWidget {
  const _ClassFormDialog({
    required this.title,
    required this.teachers,
    required this.initialName,
    required this.initialTeacherId,
  });

  final String title;
  final List<AppUser> teachers;
  final String initialName;
  final String? initialTeacherId;

  @override
  State<_ClassFormDialog> createState() => _ClassFormDialogState();
}

class _ClassFormDialogState extends State<_ClassFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late String? _teacherId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    final ids = widget.teachers.map((t) => t.id).toSet();
    // Keep a valid initial selection only if that teacher is in the list.
    _teacherId = ids.contains(widget.initialTeacherId) ? widget.initialTeacherId : null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Class name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a name' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _teacherId,
              decoration: const InputDecoration(labelText: 'Teacher'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Unassigned')),
                for (final t in widget.teachers)
                  DropdownMenuItem(value: t.id, child: Text(t.name)),
              ],
              onChanged: (value) => setState(() => _teacherId = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop((name: _nameController.text.trim(), teacherId: _teacherId));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
