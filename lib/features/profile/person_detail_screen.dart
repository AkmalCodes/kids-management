import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/models/app_user.dart';
import '../../../core/services/photo_capture_service.dart';
import '../../../core/services/profile_service.dart';
import '../../../shared/widgets/avatar_preview.dart';
import '../../../shared/widgets/avatar_source_sheet.dart';
import '../../../shared/widgets/editable_field.dart';

// View/edit of a teacher's/parent's profile (name, phone, avatar + HR
// details: address, date of birth, emergency contact). Reached two ways: a
// director tapping a person in People > Teachers, or any user via "Profile
// details" on their own Profile tab. Editing yourself uses the self-only
// paths; a director editing someone else uses the director paths.
// Email is shown read-only -- it's the login identity (auth.users), kept in
// profiles.email by a DB trigger; changing it is an auth flow, not done here.
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
  late final TextEditingController _addressController;
  late final TextEditingController _emergencyNameController;
  late final TextEditingController _emergencyPhoneController;
  late DateTime? _dob;
  late String? _avatarPath;
  bool _saving = false;
  // Screen opens read-only; the AppBar edit icon flips this on and the
  // inputs fade in. Save pops back to the caller, so the last-saved baseline
  // is always widget.person -- cancel just restores from it.
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.person.name);
    _phoneController = TextEditingController(text: widget.person.phone);
    _addressController = TextEditingController(text: widget.person.address ?? '');
    _emergencyNameController =
        TextEditingController(text: widget.person.emergencyContactName ?? '');
    _emergencyPhoneController =
        TextEditingController(text: widget.person.emergencyContactPhone ?? '');
    _dob = widget.person.dob;
    _avatarPath = widget.person.avatarPath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
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
    // Trim to null so empty fields clear the column rather than storing ''.
    String? orNull(String v) => v.trim().isEmpty ? null : v.trim();
    final address = orNull(_addressController.text);
    final emergencyName = orNull(_emergencyNameController.text);
    final emergencyPhone = orNull(_emergencyPhoneController.text);
    // Postgres date column wants an ISO yyyy-MM-dd string (date only).
    final dob = _dob == null
        ? null
        : '${_dob!.year.toString().padLeft(4, '0')}-'
            '${_dob!.month.toString().padLeft(2, '0')}-'
            '${_dob!.day.toString().padLeft(2, '0')}';
    try {
      // Editing yourself goes through the self-only RPC (works for any
      // role); editing someone else uses the director-only policy.
      final updated = user.id == widget.person.id
          ? await service.updateOwnDetails(
              name: name,
              phone: phone,
              address: address,
              dob: dob,
              emergencyContactName: emergencyName,
              emergencyContactPhone: emergencyPhone,
            )
          : await service.updatePersonDetails(
              userId: widget.person.id,
              name: name,
              phone: phone,
              address: address,
              dob: dob,
              emergencyContactName: emergencyName,
              emergencyContactPhone: emergencyPhone,
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

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  void _startEdit() => setState(() => _editing = true);

  // Cancel = throw away unsaved edits by restoring every field from the
  // last-saved values (widget.person), then drop back to read-only.
  void _cancelEdit() {
    final p = widget.person;
    _nameController.text = p.name;
    _phoneController.text = p.phone;
    _addressController.text = p.address ?? '';
    _emergencyNameController.text = p.emergencyContactName ?? '';
    _emergencyPhoneController.text = p.emergencyContactPhone ?? '';
    setState(() {
      _dob = p.dob;
      _editing = false;
    });
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 30),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  // A read-only labelled row for values that aren't plain editable text
  // (the login email, and the date of birth in view mode). Email is
  // copyable; DOB isn't.
  Widget _readOnlyRow(BuildContext context, {required String label, required String value, bool copyable = false}) {
    final theme = Theme.of(context);
    final hasValue = value.isNotEmpty;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor)),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  hasValue ? value : 'Not provided',
                  style: hasValue
                      ? theme.textTheme.bodyLarge
                      : theme.textTheme.bodyLarge?.copyWith(color: theme.disabledColor),
                ),
              ),
              if (copyable && hasValue)
                Icon(Icons.copy_outlined, size: 18, color: theme.hintColor),
            ],
          ),
        ],
      ),
    );
    if (!(copyable && hasValue)) return row;
    return InkWell(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Copied $label to clipboard')));
      },
      child: row,
    );
  }

  @override
  Widget build(BuildContext context) {
    final roleLabel =
        widget.person.role[0].toUpperCase() + widget.person.role.substring(1);
    final email = widget.person.email ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.person.name),
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
                urlProvider: _avatarPath == null ? null : signedAvatarUrlProvider(_avatarPath!),
              ),
            ),
            // Change photo only in edit mode.
            if (_editing)
              Center(
                child: TextButton.icon(
                  onPressed: _changeAvatar,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Change photo'),
                ),
              ),
            Center(child: Chip(label: Text(roleLabel), side: BorderSide.none)),
            const SizedBox(height: 16),
            // Email is always read-only (login identity), tap to copy.
            _readOnlyRow(context, label: 'Login email', value: email, copyable: true),
            EditableField(
              label: 'Name',
              controller: _nameController,
              editing: _editing,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a name' : null,
            ),
            EditableField(
              label: 'Phone',
              controller: _phoneController,
              editing: _editing,
              keyboardType: TextInputType.phone,
              copyable: true,
            ),
            // DOB: a tappable picker while editing, a plain row when viewing.
            if (_editing)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _pickDob,
                  icon: const Icon(Icons.cake_outlined),
                  label: Text(
                    _dob == null ? 'Date of birth: not set' : 'Date of birth: ${_formatDate(_dob!)}',
                  ),
                ),
              )
            else
              _readOnlyRow(
                context,
                label: 'Date of birth',
                value: _dob == null ? '' : _formatDate(_dob!),
              ),
            EditableField(
              label: 'Address',
              controller: _addressController,
              editing: _editing,
              maxLines: 2,
            ),
            EditableField(
              label: 'Emergency contact name',
              controller: _emergencyNameController,
              editing: _editing,
            ),
            EditableField(
              label: 'Emergency contact phone',
              controller: _emergencyPhoneController,
              editing: _editing,
              keyboardType: TextInputType.phone,
              copyable: true,
            ),
            const SizedBox(height: 24),
            // Save only exists in edit mode.
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
          ],
        ),
      ),
    );
  }
}
