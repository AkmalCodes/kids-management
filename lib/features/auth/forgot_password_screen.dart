import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_controller.dart';

// Sends a password-recovery email. The link in that email deep-links back
// into the app (same com.example.test_flutter://login-callback/ scheme as
// invites), which fires a passwordRecovery auth event that routes to
// SetPasswordScreen -- so this screen's only job is capturing the email
// and kicking off the send.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _sending = false;
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      await ref.read(authControllerProvider).sendPasswordReset(_emailController.text.trim());
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sent = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send reset email: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _sent ? _confirmation(context) : _form(),
        ),
      ),
    );
  }

  Widget _confirmation(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 64),
        const SizedBox(height: 16),
        Text(
          "If an account exists for that email, we've sent a link to reset your password. "
          'Open it on this device to continue.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to sign in'),
        ),
      ],
    );
  }

  Widget _form() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Enter your email and we\'ll send you a link to set a new password.'),
          const SizedBox(height: 24),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
            validator: (v) {
              final value = v?.trim() ?? '';
              if (value.isEmpty) return 'Please enter your email';
              if (!value.contains('@')) return 'Enter a valid email';
              return null;
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _sending ? null : _send,
              child: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Send reset link'),
            ),
          ),
        ],
      ),
    );
  }
}
