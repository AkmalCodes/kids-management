import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/models/app_user.dart';
import '../../../core/services/profile_service.dart';

// Director-only view/edit of a teacher's or parent's profile. Reached by
// tapping a person in the People > Teachers list. Name and phone are
// editable (role is shown read-only). Email lives on auth.users and isn't
// readable for other users from the client, so it isn't shown here; the
// avatar likewise can't be fetched cross-user (avatars RLS is owner-only),
// so a placeholder is shown.
class PersonDetailScreen extends ConsumerStatefulWidget {
  const PersonDetailScreen({super.key, required this.person});

  final AppUser person;

  @override
  ConsumerState<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends ConsumerState<PersonDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.person.name);
    _phoneController = TextEditingController(text: widget.person.phone);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // .future not .value: this screen never watches currentUserProvider
    // earlier, so a synchronous .value read can catch it mid-load.
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return;
    setState(() => _saving = true);
    try {
      final updated = await ref.read(profileServiceProvider).updatePersonDetails(
            userId: widget.person.id,
            name: _nameController.text.trim(),
            phone: _phoneController.text.trim(),
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
    final roleLabel =
        widget.person.role[0].toUpperCase() + widget.person.role.substring(1);
    return Scaffold(
      appBar: AppBar(title: Text(widget.person.name)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Center(
              child: CircleAvatar(radius: 40, child: Icon(Icons.person_outline, size: 40)),
            ),
            const SizedBox(height: 8),
            Center(child: Chip(label: Text(roleLabel), side: BorderSide.none)),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
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
