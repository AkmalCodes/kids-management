import 'package:flutter/material.dart';

class PersonInviteResult {
  const PersonInviteResult({required this.name, required this.email, required this.phone});
  final String name;
  final String email;
  final String phone;
}

// Shared by the teacher-invite flow and the "link another parent" action --
// both just need a name/email/phone to hand off to UserManagementService.
// Returns null if the director cancels.
Future<PersonInviteResult?> showPersonInviteDialog(
  BuildContext context, {
  required String title,
}) {
  return showDialog<PersonInviteResult>(
    context: context,
    builder: (_) => _PersonInviteDialog(title: title),
  );
}

class _PersonInviteDialog extends StatefulWidget {
  const _PersonInviteDialog({required this.title});

  final String title;

  @override
  State<_PersonInviteDialog> createState() => _PersonInviteDialogState();
}

class _PersonInviteDialogState extends State<_PersonInviteDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      PersonInviteResult(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
      ),
    );
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
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) {
                final value = v?.trim() ?? '';
                if (value.isEmpty) return 'Please enter an email';
                if (!value.contains('@')) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Invite')),
      ],
    );
  }
}
