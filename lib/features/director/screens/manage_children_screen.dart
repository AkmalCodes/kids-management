import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/child.dart';
import '../../../core/controllers/child_controller.dart';
import '../../../core/controllers/user_management_controller.dart';
import '../../../shared/widgets/person_invite_dialog.dart';
import '../../../shared/widgets/row_actions_sheet.dart';
import '../../../shared/widgets/signed_avatar.dart';
import 'child_detail_screen.dart';
import 'enroll_child_screen.dart';

class ManageChildrenScreen extends ConsumerStatefulWidget {
  const ManageChildrenScreen({super.key});

  @override
  ConsumerState<ManageChildrenScreen> createState() => _ManageChildrenScreenState();
}

class _ManageChildrenScreenState extends ConsumerState<ManageChildrenScreen> {
  late Future<List<Child>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Child>> _load() => ref.read(childControllerProvider).fetchAll();

  Future<void> _enrollChild() async {
    final enrolled = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const EnrollChildScreen()),
    );
    if (enrolled != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Child enrolled and parent invited')),
    );
    setState(() {
      _future = _load();
    });
  }

  // Covers both linking a second parent, and retrying after the first
  // parent invite failed on enrollment (the child record itself would
  // already exist in that case).
  Future<void> _addParent(Child child) async {
    final result = await showPersonInviteDialog(context, title: 'Invite a parent for ${child.name}');
    if (result == null || !mounted) return;
    try {
      await ref.read(userManagementControllerProvider).inviteParent(
            email: result.email,
            name: result.name,
            childId: child.id,
            phone: result.phone,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invite sent to ${result.email}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not invite parent: $e')),
      );
    }
  }

  Future<void> _delete(Child child) async {
    if (!await confirmDelete(context,
        message: 'Delete ${child.name}? This also removes their attendance and reports.')) {
      return;
    }
    try {
      await ref.read(childControllerProvider).deleteChild(child.id);
      if (!mounted) return;
      setState(() {
        _future = _load();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    }
  }

  Future<void> _openDetail(Child child) async {
    final updated = await Navigator.of(context).push<Child>(
      MaterialPageRoute(builder: (_) => ChildDetailScreen(child: child)),
    );
    if (updated == null || !mounted) return;
    // A save returns the updated child -- refresh the list so the row
    // reflects any changed name/class.
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<Child>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final children = snapshot.data!;
          if (children.isEmpty) {
            return const Center(child: Text('No children enrolled yet.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: children.length,
            itemBuilder: (context, i) {
              final child = children[i];
              return ListTile(
                leading: SignedAvatar(
                  urlProvider: child.avatarPath == null
                      ? null
                      : signedChildAvatarUrlProvider(child.avatarPath!),
                  radius: 20,
                ),
                title: Text(child.name),
                subtitle: Text(child.className.isEmpty ? 'No class on file' : child.className),
                onTap: () => _openDetail(child),
                onLongPress: () => showRowActionsSheet(
                  context,
                  title: child.name,
                  onEdit: () => _openDetail(child),
                  onDelete: () => _delete(child),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  tooltip: 'Invite a parent',
                  onPressed: () => _addParent(child),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _enrollChild,
        tooltip: 'Enroll a child',
        child: const Icon(Icons.add),
      ),
    );
  }
}
