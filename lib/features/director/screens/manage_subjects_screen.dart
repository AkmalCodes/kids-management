import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/models/subject.dart';
import '../../../core/services/subject_service.dart';
import '../../../shared/widgets/row_actions_sheet.dart';

// Director-managed list of lesson subjects (Art, Numeracy, …). Teachers tag
// lesson plans with these, and they surface on the schedule (later). Create,
// rename, delete.
class ManageSubjectsScreen extends ConsumerStatefulWidget {
  const ManageSubjectsScreen({super.key});

  @override
  ConsumerState<ManageSubjectsScreen> createState() => _ManageSubjectsScreenState();
}

class _ManageSubjectsScreenState extends ConsumerState<ManageSubjectsScreen> {
  late Future<List<Subject>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(subjectServiceProvider).fetchAll();
  }

  // Block body, not `() =>`: an arrow would return the Future from the
  // assignment and setState rejects a callback that returns a Future.
  void _refresh() {
    setState(() {
      _future = ref.read(subjectServiceProvider).fetchAll();
    });
  }

  Future<void> _create() async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null || user.centerId == null || !mounted) return;
    final result = await _showSubjectDialog(title: 'New subject');
    if (result == null || result.name == null) return;
    try {
      await ref.read(subjectServiceProvider).createSubject(
            name: result.name!,
            centerId: user.centerId!,
            actorUid: user.id,
          );
      if (mounted) _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  Future<void> _edit(Subject subject) async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null || !mounted) return;
    final result = await _showSubjectDialog(title: 'Edit subject', initialName: subject.name);
    if (result == null) return;
    final service = ref.read(subjectServiceProvider);
    try {
      if (result.delete) {
        await service.deleteSubject(subject.id);
      } else if (result.name != null) {
        await service.updateSubject(id: subject.id, name: result.name!, actorUid: user.id);
      } else {
        return;
      }
      if (mounted) _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  Future<void> _deleteSubject(Subject subject) async {
    if (!await confirmDelete(context, message: 'Delete subject "${subject.name}"?')) return;
    try {
      await ref.read(subjectServiceProvider).deleteSubject(subject.id);
      if (mounted) _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not delete: $e')));
      }
    }
  }

  // Returns (name: entered) on save, (delete: true) on delete, or null on cancel.
  Future<({String? name, bool delete})?> _showSubjectDialog({
    required String title,
    String initialName = '',
  }) {
    return showDialog<({String? name, bool delete})>(
      context: context,
      builder: (_) => _SubjectDialog(title: title, initialName: initialName),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Subjects')),
      body: FutureBuilder<List<Subject>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load subjects:\n${snapshot.error}',
                    textAlign: TextAlign.center),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final subjects = snapshot.data!;
          if (subjects.isEmpty) {
            return const Center(child: Text('No subjects yet.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: subjects.length,
            itemBuilder: (context, i) {
              final subject = subjects[i];
              return ListTile(
                leading: const Icon(Icons.category_outlined),
                title: Text(subject.name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _edit(subject),
                onLongPress: () => showRowActionsSheet(
                  context,
                  title: subject.name,
                  onEdit: () => _edit(subject),
                  onDelete: () => _deleteSubject(subject),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _create,
        tooltip: 'New subject',
        child: const Icon(Icons.add),
      ),
    );
  }
}

// Owns its own text controller so it's disposed correctly with the dialog
// (disposing it inline via whenComplete crashes: the field is still torn
// down over the pop animation). Pops (name:) on save, (delete:true) on
// delete, or null on cancel.
class _SubjectDialog extends StatefulWidget {
  const _SubjectDialog({required this.title, required this.initialName});

  final String title;
  final String initialName;

  @override
  State<_SubjectDialog> createState() => _SubjectDialogState();
}

class _SubjectDialogState extends State<_SubjectDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialName.isNotEmpty;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Subject name'),
      ),
      actions: [
        if (isEdit)
          TextButton(
            onPressed: () => Navigator.of(context).pop((name: null, delete: true)),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final name = _controller.text.trim();
            if (name.isEmpty) return;
            Navigator.of(context).pop((name: name, delete: false));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
