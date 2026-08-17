import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/models/class_group.dart';
import '../../../core/controllers/class_controller.dart';
import '../../../core/controllers/teacher_controller.dart';
import '../../../shared/widgets/class_form_dialog.dart';
import '../../../shared/widgets/row_actions_sheet.dart';
import '../../../shared/widgets/signed_avatar.dart';
import 'class_detail_screen.dart';
import '../../../shared/widgets/app_loader.dart';

// Director's Classes sub-tab: create classes, assign a teacher, rename /
// reassign. Assigning children to a class is done from ChildDetailScreen.
class ManageClassesScreen extends ConsumerStatefulWidget {
  const ManageClassesScreen({super.key});

  @override
  ConsumerState<ManageClassesScreen> createState() => _ManageClassesScreenState();
}

class _RosterData {
  const _RosterData({required this.classes, required this.teachersById});
  final List<ClassGroup> classes;
  final Map<String, String> teachersById; // teacher id -> name
}

class _ManageClassesScreenState extends ConsumerState<ManageClassesScreen> {
  late Future<_RosterData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_RosterData> _load() async {
    final classes = await ref.read(classControllerProvider).fetchAll();
    final teachers = await ref.read(teacherControllerProvider).fetchAll();
    return _RosterData(
      classes: classes,
      teachersById: {for (final t in teachers) t.id: t.name},
    );
  }

  Future<void> _create() async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null || user.centerId == null || !mounted) return;
    final teachers = await ref.read(teacherControllerProvider).fetchAll();
    if (!mounted) return;
    final result = await showClassFormDialog(context, title: 'New class', teachers: teachers);
    if (result == null) return;
    try {
      await ref.read(classControllerProvider).createClass(
            name: result.name,
            teacherId: result.teacherId,
            centerId: user.centerId!,
            actorUid: user.id,
          );
      if (!mounted) return;
      // Block body (not `() =>`): an arrow would return the Future from the
      // assignment, and setState rejects a callback that returns a Future.
      setState(() {
        _future = _load();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save class: $e')));
    }
  }

  // Editing (name, teacher, and photo) happens on a full detail screen --
  // like children/teachers -- because a class now has a picture. Refresh the
  // list if it came back changed.
  Future<void> _edit(ClassGroup classGroup) async {
    final result = await Navigator.of(context).push<ClassGroup>(
      MaterialPageRoute(builder: (_) => ClassDetailScreen(classGroup: classGroup)),
    );
    if (result != null && mounted) {
      setState(() {
        _future = _load();
      });
    }
  }

  Future<void> _delete(ClassGroup classGroup) async {
    if (!await confirmDelete(context,
        message: 'Delete "${classGroup.name}"? Children in it become unassigned.')) {
      return;
    }
    try {
      await ref.read(classControllerProvider).deleteClass(classGroup.id);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<_RosterData>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: AppLoader());
          }
          final data = snapshot.data!;
          if (data.classes.isEmpty) {
            return const Center(child: Text('No classes yet.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: data.classes.length,
            itemBuilder: (context, i) {
              final classGroup = data.classes[i];
              final teacherName = classGroup.teacherId == null
                  ? 'No teacher assigned'
                  : (data.teachersById[classGroup.teacherId] ?? 'Unknown teacher');
              return ListTile(
                leading: SignedAvatar(
                  radius: 20,
                  urlProvider: classGroup.avatarPath == null
                      ? null
                      : signedClassAvatarUrlProvider(classGroup.avatarPath!),
                ),
                title: Text(classGroup.name),
                subtitle: Text(teacherName),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _edit(classGroup),
                onLongPress: () => showRowActionsSheet(
                  context,
                  title: classGroup.name,
                  onEdit: () => _edit(classGroup),
                  onDelete: () => _delete(classGroup),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _create,
        tooltip: 'New class',
        child: const Icon(Icons.add),
      ),
    );
  }
}
