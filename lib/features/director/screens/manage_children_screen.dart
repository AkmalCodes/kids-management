import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/child.dart';
import '../../../core/services/child_service.dart';
import '../../../core/services/user_management_service.dart';
import '../../../shared/widgets/person_invite_dialog.dart';
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

  Future<List<Child>> _load() => ref.read(childServiceProvider).fetchAll();

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
      await ref.read(userManagementServiceProvider).inviteParent(
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
                leading: const CircleAvatar(child: Icon(Icons.child_care_outlined)),
                title: Text(child.name),
                subtitle: Text(child.className.isEmpty ? 'No class on file' : child.className),
                onTap: () => _openDetail(child),
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
