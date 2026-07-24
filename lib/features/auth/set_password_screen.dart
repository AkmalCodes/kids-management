import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_service.dart';

// Reached two ways, both after a valid session is already established from
// an emailed link:
//  - invite: a newly-invited account whose profile has must_set_password
//  - recovery: a "forgot password" link (passwordRecovery auth event)
// Either way the job is the same: capture a new password for the current
// user. clearMustSetPasswordFlag is only true for the invite case.
class SetPasswordScreen extends ConsumerStatefulWidget {
  const SetPasswordScreen({super.key, this.clearMustSetPasswordFlag = true});

  final bool clearMustSetPasswordFlag;

  @override
  ConsumerState<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends ConsumerState<SetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final auth = ref.read(authServiceProvider);
    try {
      await auth.updatePassword(_passwordController.text);
      if (widget.clearMustSetPasswordFlag) {
        await auth.completePasswordSetup();
      }
      // Re-read the profile so AuthGate re-routes: for invites the cleared
      // flag now sends them on to their role shell.
      ref.invalidate(currentUserProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not set password: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set your password')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Choose a password to finish setting up your account.'),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password'),
                  validator: (v) {
                    final value = v ?? '';
                    if (value.length < 6) return 'At least 6 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Confirm password'),
                  validator: (v) =>
                      v != _passwordController.text ? 'Passwords do not match' : null,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save password'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
