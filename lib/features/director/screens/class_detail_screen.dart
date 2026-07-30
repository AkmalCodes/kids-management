import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/class_group.dart';
import '../../../core/services/class_service.dart';
import '../../../core/services/photo_capture_service.dart';
import '../../../core/services/teacher_service.dart';
import '../../../shared/widgets/avatar_source_sheet.dart';
import '../../../shared/widgets/signed_avatar.dart';

// Director-only view/edit of one class. Reached by tapping a class in
// People > Classes. Edits the photo (class-avatars bucket), name, and
// assigned teacher; saving writes back via ClassService.updateClass
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
  late String? _teacherId;
  late String? _avatarPath;
  late Future<List<AppUser>> _teachersFuture;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.classGroup.name);
    _teacherId = widget.classGroup.teacherId;
    _avatarPath = widget.classGroup.avatarPath;
    _teachersFuture = ref.read(teacherServiceProvider).fetchAll();
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
    final capture = ref.read(photoCaptureServiceProvider);
    final photo = source == AvatarSource.gallery
        ? await capture.pickFromGallery()
        : await capture.captureFromCamera();
    if (photo == null) return;
    final service = ref.read(classServiceProvider);
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
      final updated = await ref.read(classServiceProvider).updateClass(
            id: widget.classGroup.id,
            name: _nameController.text.trim(),
            teacherId: _teacherId,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.classGroup.name)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: SignedAvatar(
                radius: 56,
                urlProvider:
                    _avatarPath == null ? null : signedClassAvatarUrlProvider(_avatarPath!),
              ),
            ),
            Center(
              child: TextButton.icon(
                onPressed: _changeAvatar,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Change photo'),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Class name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a name' : null,
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<AppUser>>(
              future: _teachersFuture,
              builder: (context, snapshot) {
                final teachers = snapshot.data ?? [];
                // Keep the current teacher selectable even before the list
                // loads / if they aren't in the fetched set.
                final ids = teachers.map((t) => t.id).toSet();
                return DropdownButtonFormField<String?>(
                  initialValue:
                      (_teacherId != null && ids.contains(_teacherId)) ? _teacherId : null,
                  decoration: const InputDecoration(labelText: 'Teacher'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Unassigned')),
                    for (final t in teachers)
                      DropdownMenuItem(value: t.id, child: Text(t.name)),
                  ],
                  onChanged: (value) => setState(() => _teacherId = value),
                );
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}
