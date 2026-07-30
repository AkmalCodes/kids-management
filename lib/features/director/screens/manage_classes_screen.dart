import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/models/class_group.dart';
import '../../../core/services/class_service.dart';
import '../../../core/services/teacher_service.dart';
import '../../../shared/widgets/class_form_dialog.dart';

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
    final classes = await ref.read(classServiceProvider).fetchAll();
    final teachers = await ref.read(teacherServiceProvider).fetchAll();
    return _RosterData(
      classes: classes,
      teachersById: {for (final t in teachers) t.id: t.name},
    );
  }

  Future<void> _create() async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null || user.centerId == null || !mounted) return;
    final teachers = await ref.read(teacherServiceProvider).fetchAll();
    if (!mounted) return;
    final result = await showClassFormDialog(context, title: 'New class', teachers: teachers);
    if (result == null) return;
    try {
      await ref.read(classServiceProvider).createClass(
            name: result.name,
            teacherId: result.teacherId,
            centerId: user.centerId!,
            actorUid: user.id,
          );
      if (!mounted) return;
      setState(() => _future = _load());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save class: $e')));
    }
  }

  Future<void> _edit(ClassGroup classGroup) async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null || !mounted) return;
    final teachers = await ref.read(teacherServiceProvider).fetchAll();
    if (!mounted) return;
    final result = await showClassFormDialog(
      context,
      title: 'Edit class',
      teachers: teachers,
      initialName: classGroup.name,
      initialTeacherId: classGroup.teacherId,
    );
    if (result == null) return;
    try {
      await ref.read(classServiceProvider).updateClass(
            id: classGroup.id,
            name: result.name,
            teacherId: result.teacherId,
            actorUid: user.id,
          );
      if (!mounted) return;
      setState(() => _future = _load());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save class: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<_RosterData>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
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
                leading: const CircleAvatar(child: Icon(Icons.groups_outlined)),
                title: Text(classGroup.name),
                subtitle: Text(teacherName),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _edit(classGroup),
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
