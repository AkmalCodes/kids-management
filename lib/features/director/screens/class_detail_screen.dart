import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/class_group.dart';
import '../../../core/controllers/class_controller.dart';
import '../../../core/controllers/photo_capture_controller.dart';
import '../../../core/controllers/teacher_controller.dart';
import '../../../shared/widgets/avatar_preview.dart';
import '../../../shared/widgets/avatar_source_sheet.dart';
import '../../../shared/widgets/editable_field.dart';
import '../../../shared/widgets/teacher_multi_select.dart';
import '../../../shared/widgets/app_loader.dart';

// Director-only view/edit of one class. Reached by tapping a class in
// People > Classes. Edits the photo (class-avatars bucket), name, and
// assigned teacher; saving writes back via ClassController.updateClass
// (director-only per RLS) and pops the updated class so the list refreshes.
// (Creating a class stays a dialog -- there's no class_id to key the photo
// upload path until the row exists, so a picture is added by opening it here
// afterwards.)
class ClassDetailScreen extends ConsumerStatefulWidget {
  const ClassDetailScreen({super.key, required this.classGroup});

  final ClassGroup classGroup;

  @override
  ConsumerState<ClassDetailScreen> createState() => _ClassDetailScreenState();
}

class _ClassDetailScreenState extends ConsumerState<ClassDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late List<String> _teacherIds;
  late String? _avatarPath;
  late Future<List<AppUser>> _teachersFuture;
  bool _saving = false;
  // Read-only until the AppBar edit icon flips this on (inputs fade in).
  // Save pops, so widget.classGroup is the last-saved baseline for cancel.
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.classGroup.name);
    _teacherIds = [...widget.classGroup.teacherIds];
    _avatarPath = widget.classGroup.avatarPath;
    _teachersFuture = ref.read(teacherControllerProvider).fetchAll();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // Immediate (independent of Save): pick -> upload -> write the path onto
  // the class row -> refresh. Same flow as the child-avatar editor.
  Future<void> _changeAvatar() async {
    final source = await showAvatarSourceSheet(context);
    if (source == null) return;
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return;
    final capture = ref.read(photoCaptureControllerProvider);
    final photo = source == AvatarSource.gallery
        ? await capture.pickFromGallery()
        : await capture.captureFromCamera();
    if (photo == null) return;
    final service = ref.read(classControllerProvider);
    try {
      final path =
          await service.uploadClassAvatar(classId: widget.classGroup.id, photo: photo);
      await service.setClassAvatarPath(
          classId: widget.classGroup.id, path: path, actorUid: user.id);
      if (!mounted) return;
      ref.invalidate(signedClassAvatarUrlProvider(path));
      setState(() => _avatarPath = path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update photo: $e')),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return;
    setState(() => _saving = true);
    try {
      final updated = await ref.read(classControllerProvider).updateClass(
            id: widget.classGroup.id,
            name: _nameController.text.trim(),
            teacherIds: _teacherIds,
            actorUid: user.id,
          );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save changes: $e')),
      );
    }
  }

  void _startEdit() => setState(() => _editing = true);

  // Cancel = discard unsaved edits by restoring from the last-saved values
  // (widget.classGroup), then drop back to read-only.
  void _cancelEdit() {
    _nameController.text = widget.classGroup.name;
    setState(() {
      _teacherIds = [...widget.classGroup.teacherIds];
      _editing = false;
    });
  }

  // Read-only labelled row (for view mode: teacher).
  Widget _readOnlyRow(BuildContext context, {required String label, required String value}) {
    final theme = Theme.of(context);
    final hasValue = value.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor)),
          const SizedBox(height: 2),
          Text(
            hasValue ? value : 'Not provided',
            style: hasValue
                ? theme.textTheme.bodyLarge
                : theme.textTheme.bodyLarge?.copyWith(color: theme.disabledColor),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.classGroup.name),
        actions: [
          IconButton(
            icon: Icon(_editing ? Icons.close : Icons.edit_outlined),
            tooltip: _editing ? 'Cancel' : 'Edit',
            onPressed: _editing ? _cancelEdit : _startEdit,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: AvatarWithPreview(
                radius: 56,
                urlProvider:
                    _avatarPath == null ? null : signedClassAvatarUrlProvider(_avatarPath!),
              ),
            ),
            if (_editing)
              Center(
                child: TextButton.icon(
                  onPressed: _changeAvatar,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Change photo'),
                ),
              ),
            const SizedBox(height: 8),
            EditableField(
              label: 'Class name',
              controller: _nameController,
              editing: _editing,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a name' : null,
            ),
            // Teacher(s): multi-select while editing; joined names when viewing.
            FutureBuilder<List<AppUser>>(
              future: _teachersFuture,
              builder: (context, snapshot) {
                final teachers = snapshot.data ?? [];
                // Fetch failed: don't fall through to the null-data path (which
                // would show "…" forever in view mode, or render every chip as
                // "Unknown teacher" with a dead Add control in edit mode -- the
                // director could delete a teacher they can't identify).
                if (snapshot.hasError) {
                  return _readOnlyRow(context,
                      label: 'Teacher', value: "Couldn't load teachers");
                }
                if (!_editing) {
                  final assigned = widget.classGroup.teacherIds;
                  String value;
                  if (assigned.isEmpty) {
                    value = 'Unassigned';
                  } else if (snapshot.data == null) {
                    value = '…'; // still loading the teacher list
                  } else {
                    String nameFor(String id) {
                      for (final t in teachers) {
                        if (t.id == id) return t.name;
                      }
                      return 'Unknown teacher';
                    }

                    value = assigned.map(nameFor).join(', ');
                  }
                  return _readOnlyRow(context, label: 'Teacher', value: value);
                }
                return TeacherMultiSelect(
                  allTeachers: teachers,
                  selectedIds: _teacherIds,
                  onChanged: (ids) => setState(() => _teacherIds = ids),
                );
              },
            ),
            const SizedBox(height: 24),
            if (_editing)
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const AppLoader(size: 20, delayed: false)
                    : const Text('Save changes'),
              ),
          ],
        ),
      ),
    );
  }
}
