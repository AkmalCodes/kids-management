import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/child.dart';
import '../../../core/services/child_service.dart';
import '../../../core/services/teacher_service.dart';

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
  late final TextEditingController _classController;
  late final TextEditingController _allergiesController;
  late final TextEditingController _notesController;

  late DateTime _dob;
  late String? _teacherId;
  late Future<List<AppUser>> _teachersFuture;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.child;
    _nameController = TextEditingController(text: c.name);
    _classController = TextEditingController(text: c.className);
    _allergiesController = TextEditingController(text: c.allergies);
    _notesController = TextEditingController(text: c.notes);
    _dob = c.dob;
    _teacherId = c.teacherId;
    _teachersFuture = ref.read(teacherServiceProvider).fetchAll();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _classController.dispose();
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
              className: _classController.text.trim(),
              teacherId: _teacherId,
              clearTeacherId: _teacherId == null,
              allergies: _allergiesController.text.trim(),
              notes: _notesController.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.child.name)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a name' : null,
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _pickDob,
              icon: const Icon(Icons.cake_outlined),
              label: Text('Date of birth: ${_formatDate(_dob)}  •  Age $_ageYears'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _classController,
              decoration: const InputDecoration(labelText: 'Class'),
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
            const SizedBox(height: 12),
            TextFormField(
              controller: _allergiesController,
              decoration: const InputDecoration(labelText: 'Allergies'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 3,
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
