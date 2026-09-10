import 'package:flutter/material.dart';
import '../../core/models/app_user.dart';
import 'teacher_multi_select.dart';

typedef ClassFormResult = ({String name, List<String> teacherIds});

// Create/edit-a-class dialog: name + a multi-teacher picker. Returns null on
// cancel. Shared by ManageClassesScreen's create and edit flows.
Future<ClassFormResult?> showClassFormDialog(
  BuildContext context, {
  required String title,
  required List<AppUser> teachers,
  String initialName = '',
  List<String> initialTeacherIds = const [],
}) {
  return showDialog<ClassFormResult>(
    context: context,
    builder: (_) => _ClassFormDialog(
      title: title,
      teachers: teachers,
      initialName: initialName,
      initialTeacherIds: initialTeacherIds,
    ),
  );
}

class _ClassFormDialog extends StatefulWidget {
  const _ClassFormDialog({
    required this.title,
    required this.teachers,
    required this.initialName,
    required this.initialTeacherIds,
  });

  final String title;
  final List<AppUser> teachers;
  final String initialName;
  final List<String> initialTeacherIds;

  @override
  State<_ClassFormDialog> createState() => _ClassFormDialogState();
}

class _ClassFormDialogState extends State<_ClassFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  // Local working copy; TeacherMultiSelect reports the full new list back.
  late List<String> _teacherIds;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    final ids = widget.teachers.map((t) => t.id).toSet();
    // Keep only initial ids that still map to a teacher in the list.
    _teacherIds = widget.initialTeacherIds.where(ids.contains).toList();
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Class name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a name' : null,
            ),
            const SizedBox(height: 12),
            TeacherMultiSelect(
              allTeachers: widget.teachers,
              selectedIds: _teacherIds,
              onChanged: (ids) => setState(() => _teacherIds = ids),
            ),
          ],
        ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop((
              name: _nameController.text.trim(),
              teacherIds: _teacherIds,
            ));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
