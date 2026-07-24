import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/child.dart';
import '../../../core/services/child_service.dart';
import '../../../core/services/teacher_service.dart';
import '../../../core/services/user_management_service.dart';

// One form covers both halves of "enroll a child": the child record itself,
// and inviting the first parent account linked to it -- matches how a
// director actually does this in one sitting, rather than two separate
// screens.
class EnrollChildScreen extends ConsumerStatefulWidget {
  const EnrollChildScreen({super.key});

  @override
  ConsumerState<EnrollChildScreen> createState() => _EnrollChildScreenState();
}

class _EnrollChildScreenState extends ConsumerState<EnrollChildScreen> {
  final _formKey = GlobalKey<FormState>();
  final _childNameController = TextEditingController();
  final _classController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _notesController = TextEditingController();
  final _parentNameController = TextEditingController();
  final _parentEmailController = TextEditingController();
  final _parentPhoneController = TextEditingController();

  DateTime _dob = DateTime(DateTime.now().year - 2);
  String? _selectedTeacherId;
  late Future<List<AppUser>> _teachersFuture;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _teachersFuture = ref.read(teacherServiceProvider).fetchAll();
  }

  @override
  void dispose() {
    _childNameController.dispose();
    _classController.dispose();
    _allergiesController.dispose();
    _notesController.dispose();
    _parentNameController.dispose();
    _parentEmailController.dispose();
    _parentPhoneController.dispose();
    super.dispose();
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
    // .future (not .value): this screen never watches currentUserProvider
    // earlier (unlike screens whose initState() already resolves it via
    // _load()), so nothing has warmed the underlying stream up yet -- a
    // synchronous .value read here would just catch it mid-AsyncLoading.
    final user = await ref.read(currentUserProvider.future);
    final centerId = user?.centerId;
    if (user == null || centerId == null) return;

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final child = await ref.read(childServiceProvider).createChild(
            Child(
              id: '',
              name: _childNameController.text.trim(),
              dob: _dob,
              centerId: centerId,
              className: _classController.text.trim(),
              teacherId: _selectedTeacherId,
              allergies: _allergiesController.text.trim(),
              notes: _notesController.text.trim(),
              enrolledAt: now,
              createdAt: now,
              updatedAt: now,
              createdBy: user.id,
              updatedBy: user.id,
            ),
          );
      await ref.read(userManagementServiceProvider).inviteParent(
            email: _parentEmailController.text.trim(),
            name: _parentNameController.text.trim(),
            childId: child.id,
            phone: _parentPhoneController.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not enroll child: $e')),
      );
    }
  }

  String _formatDate(DateTime date) {
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    return '$dd/$mm/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enroll Child')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Child', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextFormField(
              controller: _childNameController,
              decoration: const InputDecoration(labelText: "Child's name"),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a name' : null,
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _pickDob,
              icon: const Icon(Icons.cake_outlined),
              label: Text('Date of birth: ${_formatDate(_dob)}'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _classController,
              decoration: const InputDecoration(labelText: 'Class (optional)'),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<AppUser>>(
              future: _teachersFuture,
              builder: (context, snapshot) {
                final teachers = snapshot.data ?? [];
                return DropdownButtonFormField<String>(
                  initialValue: _selectedTeacherId,
                  decoration: const InputDecoration(labelText: 'Teacher (optional)'),
                  items: [
                    for (final teacher in teachers)
                      DropdownMenuItem(value: teacher.id, child: Text(teacher.name)),
                  ],
                  onChanged: (value) => setState(() => _selectedTeacherId = value),
                );
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _allergiesController,
              decoration: const InputDecoration(labelText: 'Allergies (optional)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            Text('Parent', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextFormField(
              controller: _parentNameController,
              decoration: const InputDecoration(labelText: "Parent's name"),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _parentEmailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: "Parent's email"),
              validator: (v) {
                final value = v?.trim() ?? '';
                if (value.isEmpty) return 'Please enter an email';
                if (!value.contains('@')) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _parentPhoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: "Parent's phone (optional)"),
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
                  : const Text('Enroll child & invite parent'),
            ),
          ],
        ),
      ),
    );
  }
}
