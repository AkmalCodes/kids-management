import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_controller.dart';
import 'forgot_password_screen.dart';
import '../../shared/widgets/app_loader.dart';
import '../../shared/widgets/app_logo.dart';

// ConsumerStatefulWidget instead of plain StatefulWidget: this screen needs
// both local UI state (text controllers, loading/error flags via setState)
// AND access to Riverpod providers (authControllerProvider) via `ref`.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  // GlobalKey<FormState> lets us imperatively call validate() on the whole
  // Form below (checks every TextFormField's validator at once) instead of
  // tracking each field's valid/invalid state ourselves.
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  // Focus nodes drive the placeholder fade below — Material's default
  // labelText instead slides the label to the top-left on focus, which
  // isn't the effect we want here.
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Rebuild whenever focus changes so the AnimatedOpacity widgets below
    // pick up the new target opacity and animate to it.
    _emailFocusNode.addListener(_onFocusChange);
    _passwordFocusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() => setState(() {});

  @override
  void dispose() {
    // Controllers and focus nodes hold native resources outside Dart's
    // garbage collector — must be disposed manually or they leak every
    // time this screen rebuilds.
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      // ref.read (not ref.watch) here: we only need authService once, for
      // this one-off action — watch is for values a widget should rebuild
      // in response to, which doesn't apply inside a button callback.
      await ref.read(authControllerProvider).signIn(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      // No manual navigation on success: AuthGate (Task 6) watches
      // currentUserProvider and swaps to RoleRouter automatically once
      // Supabase's onAuthStateChange fires.
    } catch (_) {
      setState(() => _error = 'Invalid email or password. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(size: 96),
                const SizedBox(height: 16),
                const Text(
                  'Childcare Manager',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _emailController,
                  focusNode: _emailFocusNode,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    // `hint` (a widget) instead of `hintText` (a string) —
                    // lets us control its opacity ourselves via focus,
                    // while Flutter still positions it correctly relative
                    // to the prefixIcon.
                    hint: AnimatedOpacity(
                      key: const Key('email-hint-opacity'),
                      opacity: _emailFocusNode.hasFocus ? 0 : 1,
                      duration: const Duration(milliseconds: 150),
                      child: const Text('Email'),
                    ),
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Please enter your email' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  focusNode: _passwordFocusNode,
                  obscureText: true,
                  decoration: InputDecoration(
                    hint: AnimatedOpacity(
                      key: const Key('password-hint-opacity'),
                      opacity: _passwordFocusNode.hasFocus ? 0 : 1,
                      duration: const Duration(milliseconds: 150),
                      child: const Text('Password'),
                    ),
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Please enter your password' : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _signIn,
                    child: _loading
                        ? const AppLoader(size: 20, delayed: false)
                        : const Text('Sign In'),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ForgotPasswordScreen(),
                            ),
                          ),
                  child: const Text('Forgot password?'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
