import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/models/app_user.dart';
import '../../../core/services/photo_capture_service.dart';
import '../../../core/services/profile_service.dart';
import '../../../shared/widgets/avatar_source_sheet.dart';
import '../../../shared/widgets/signed_avatar.dart';

// View/edit of a teacher's/parent's profile (name, phone, avatar). Reached
// two ways: a director tapping a person in People > Teachers, or any user
// via "Profile details" on their own Profile tab. Editing yourself uses the
// self-only paths; a director editing someone else uses the director paths.
// Email lives on auth.users and isn't readable cross-user from the client,
// so it isn't shown here.
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
  late String? _avatarPath;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.person.name);
    _phoneController = TextEditingController(text: widget.person.phone);
    _avatarPath = widget.person.avatarPath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // Immediate (not tied to the Save button): pick -> upload -> write the
  // path onto the profile -> refresh. Self writes their own path via the
  // RPC; a director writes another user's path via the director policy.
  Future<void> _changeAvatar() async {
    final source = await showAvatarSourceSheet(context);
    if (source == null) return;
    final me = await ref.read(currentUserProvider.future);
    if (me == null) return;
    final capture = ref.read(photoCaptureServiceProvider);
    final photo = source == AvatarSource.gallery
        ? await capture.pickFromGallery()
        : await capture.captureFromCamera();
    if (photo == null) return;
    final service = ref.read(profileServiceProvider);
    try {
      final path = await service.uploadAvatar(userId: widget.person.id, photo: photo);
      if (me.id == widget.person.id) {
        await service.setAvatarPath(path);
        ref.invalidate(currentUserProvider);
      } else {
        await service.setAvatarPathFor(userId: widget.person.id, path: path, actorUid: me.id);
      }
      if (!mounted) return;
      // Drop any cached signed URL for this path so the new image is shown.
      ref.invalidate(signedAvatarUrlProvider(path));
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
    // .future not .value: this screen never watches currentUserProvider
    // earlier, so a synchronous .value read can catch it mid-load.
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return;
    setState(() => _saving = true);
    final service = ref.read(profileServiceProvider);
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    try {
      // Editing yourself goes through the self-only RPC (works for any
      // role); editing someone else uses the director-only policy.
      final updated = user.id == widget.person.id
          ? await service.updateOwnDetails(name: name, phone: phone)
          : await service.updatePersonDetails(
              userId: widget.person.id,
              name: name,
              phone: phone,
              actorUid: user.id,
            );
      if (!mounted) return;
      // Self-edits change the current user's own profile, so refresh it.
      if (user.id == widget.person.id) ref.invalidate(currentUserProvider);
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
            Center(
              child: SignedAvatar(
                urlProvider: _avatarPath == null ? null : signedAvatarUrlProvider(_avatarPath!),
              ),
            ),
            Center(
              child: TextButton.icon(
                onPressed: _changeAvatar,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Change photo'),
              ),
            ),
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
