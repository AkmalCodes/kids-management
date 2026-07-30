import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/child.dart';
import '../../../core/models/class_group.dart';
import '../../../core/services/child_service.dart';
import '../../../core/services/class_service.dart';
import '../../../core/services/photo_capture_service.dart';
import '../../../core/services/profile_service.dart';
import '../../../core/services/teacher_service.dart';
import '../../../shared/widgets/avatar_preview.dart';
import '../../../shared/widgets/avatar_source_sheet.dart';
import '../../../shared/widgets/editable_field.dart';
import '../../../shared/widgets/signed_avatar.dart';

// Director-only view/edit of a single child's details. Reached by tapping a
// child in the People > Children list. Every field is editable; saving
// writes back via ChildService.updateChild (director-only per RLS) and pops
// the updated child so the list can refresh.
class ChildDetailScreen extends ConsumerStatefulWidget {
  const ChildDetailScreen({super.key, required this.child});

  final Child child;

  @override
  ConsumerState<ChildDetailScreen> createState() => _ChildDetailScreenState();
}

class _ChildDetailScreenState extends ConsumerState<ChildDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _allergiesController;
  late final TextEditingController _notesController;

  late DateTime _dob;
  late String? _teacherId;
  late String? _classId;
  late String? _avatarPath;
  late Future<List<AppUser>> _teachersFuture;
  late Future<List<ClassGroup>> _classesFuture;
  late Future<List<AppUser>> _parentsFuture;
  bool _saving = false;
  // Read-only until the AppBar edit icon flips this on (inputs fade in).
  // Save pops, so widget.child is always the last-saved baseline for cancel.
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    final c = widget.child;
    _nameController = TextEditingController(text: c.name);
    _allergiesController = TextEditingController(text: c.allergies);
    _notesController = TextEditingController(text: c.notes);
    _parentsFuture = ref.read(childServiceProvider).fetchParentsForChild(c.id);
    _dob = c.dob;
    _teacherId = c.teacherId;
    _classId = c.classId;
    _avatarPath = c.avatarPath;
    _teachersFuture = ref.read(teacherServiceProvider).fetchAll();
    _classesFuture = ref.read(classServiceProvider).fetchAll();
  }

  // Immediate (independent of the Save button): pick -> upload -> write the
  // avatar path onto the child row -> refresh.
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
    final service = ref.read(childServiceProvider);
    try {
      final path = await service.uploadChildAvatar(childId: widget.child.id, photo: photo);
      await service.setChildAvatarPath(childId: widget.child.id, path: path, actorUid: user.id);
      if (!mounted) return;
      ref.invalidate(signedChildAvatarUrlProvider(path));
      setState(() => _avatarPath = path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update photo: $e')),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _allergiesController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // Whole years, flooring — the usual way a child's age reads.
  int get _ageYears {
    final now = DateTime.now();
    var age = now.year - _dob.year;
    if (now.month < _dob.month || (now.month == _dob.month && now.day < _dob.day)) {
      age--;
    }
    return age;
  }

  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob,
      firstDate: DateTime(DateTime.now().year - 6),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  void _startEdit() => setState(() => _editing = true);

  // Cancel = discard unsaved edits by restoring every field from the
  // last-saved values (widget.child), then drop back to read-only.
  void _cancelEdit() {
    final c = widget.child;
    _nameController.text = c.name;
    _allergiesController.text = c.allergies;
    _notesController.text = c.notes;
    setState(() {
      _dob = c.dob;
      _teacherId = c.teacherId;
      _classId = c.classId;
      _editing = false;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // .future not .value: this screen never watches currentUserProvider
    // earlier, so a synchronous .value read can catch it mid-load.
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return;

    setState(() => _saving = true);
    try {
      final updated = await ref.read(childServiceProvider).updateChild(
            widget.child.copyWith(
              name: _nameController.text.trim(),
              dob: _dob,
              teacherId: _teacherId,
              clearTeacherId: _teacherId == null,
              classId: _classId,
              clearClassId: _classId == null,
              allergies: _allergiesController.text.trim(),
              notes: _notesController.text.trim(),
              avatarPath: _avatarPath,
              updatedBy: user.id,
            ),
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

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  // Read-only labelled row (for view mode: DOB, class, teacher).
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
        title: Text(widget.child.name),
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
                    _avatarPath == null ? null : signedChildAvatarUrlProvider(_avatarPath!),
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
              label: 'Name',
              controller: _nameController,
              editing: _editing,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a name' : null,
            ),
            // DOB: a picker while editing; a plain row (with age) when viewing.
            if (_editing)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _pickDob,
                  icon: const Icon(Icons.cake_outlined),
                  label: Text('Date of birth: ${_formatDate(_dob)}  •  Age $_ageYears'),
                ),
              )
            else
              _readOnlyRow(
                context,
                label: 'Date of birth',
                value: '${_formatDate(_dob)}  •  Age $_ageYears',
              ),
            // Class: dropdown while editing; resolved name when viewing.
            FutureBuilder<List<ClassGroup>>(
              future: _classesFuture,
              builder: (context, snapshot) {
                final classes = snapshot.data ?? [];
                if (!_editing) {
                  var name = 'Unassigned';
                  if (_classId != null) {
                    name = '…'; // still loading the class list
                    for (final c in classes) {
                      if (c.id == _classId) name = c.name;
                    }
                  }
                  return _readOnlyRow(context, label: 'Class', value: name);
                }
                final ids = classes.map((c) => c.id).toSet();
                return DropdownButtonFormField<String?>(
                  initialValue: (_classId != null && ids.contains(_classId)) ? _classId : null,
                  decoration: const InputDecoration(
                    labelText: 'Class',
                    helperText: 'Drives the schedule the parent sees',
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Unassigned')),
                    for (final c in classes)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (value) => setState(() => _classId = value),
                );
              },
            ),
            // Class teacher: dropdown while editing; resolved name when viewing.
            FutureBuilder<List<AppUser>>(
              future: _teachersFuture,
              builder: (context, snapshot) {
                final teachers = snapshot.data ?? [];
                if (!_editing) {
                  var name = 'Unassigned';
                  if (_teacherId != null) {
                    name = '…'; // still loading the teacher list
                    for (final t in teachers) {
                      if (t.id == _teacherId) name = t.name;
                    }
                  }
                  return _readOnlyRow(context, label: 'Class teacher', value: name);
                }
                // Keep the current teacher selectable even before the list
                // loads / if they aren't in the fetched set.
                final ids = teachers.map((t) => t.id).toSet();
                return DropdownButtonFormField<String?>(
                  initialValue: (_teacherId != null && ids.contains(_teacherId)) ? _teacherId : null,
                  decoration: const InputDecoration(labelText: 'Class teacher'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Unassigned')),
                    for (final t in teachers)
                      DropdownMenuItem(value: t.id, child: Text(t.name)),
                  ],
                  onChanged: (value) => setState(() => _teacherId = value),
                );
              },
            ),
            EditableField(
              label: 'Allergies',
              controller: _allergiesController,
              editing: _editing,
            ),
            EditableField(
              label: 'Notes',
              controller: _notesController,
              editing: _editing,
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            if (_editing)
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
            const SizedBox(height: 24),
            Text('Parents', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            FutureBuilder<List<AppUser>>(
              future: _parentsFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(8),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final parents = snapshot.data!;
                if (parents.isEmpty) {
                  return const Text('No parents linked yet.');
                }
                return Column(
                  children: [
                    for (final parent in parents)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: SignedAvatar(
                          urlProvider: parent.avatarPath == null
                              ? null
                              : signedAvatarUrlProvider(parent.avatarPath!),
                          radius: 20,
                        ),
                        title: Text(parent.name),
                        subtitle: Text(
                          parent.email ?? 'No email on file',
                          style: parent.email == null
                              ? TextStyle(color: Theme.of(context).disabledColor)
                              : null,
                        ),
                        // Tap a parent's email to copy it.
                        trailing: parent.email == null
                            ? null
                            : const Icon(Icons.copy_outlined, size: 18),
                        onTap: parent.email == null
                            ? null
                            : () async {
                                await Clipboard.setData(ClipboardData(text: parent.email!));
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Copied email to clipboard')),
                                );
                              },
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
