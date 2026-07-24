import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/app_user.dart';
import '../../../core/services/teacher_service.dart';
import '../../../core/services/user_management_service.dart';
import '../../../shared/widgets/person_invite_dialog.dart';
import 'person_detail_screen.dart';

class ManageTeachersScreen extends ConsumerStatefulWidget {
  const ManageTeachersScreen({super.key});

  @override
  ConsumerState<ManageTeachersScreen> createState() => _ManageTeachersScreenState();
}

class _ManageTeachersScreenState extends ConsumerState<ManageTeachersScreen> {
  late Future<List<AppUser>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<AppUser>> _load() => ref.read(teacherServiceProvider).fetchAll();

  Future<void> _addTeacher() async {
    final result = await showPersonInviteDialog(context, title: 'Invite a teacher');
    if (result == null || !mounted) return;
    try {
      await ref.read(userManagementServiceProvider).inviteTeacher(
            email: result.email,
            name: result.name,
            phone: result.phone,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invite sent to ${result.email}')),
      );
      setState(() {
        _future = _load();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create teacher: $e')),
      );
    }
  }

  Future<void> _openDetail(AppUser teacher) async {
    final updated = await Navigator.of(context).push<AppUser>(
      MaterialPageRoute(builder: (_) => PersonDetailScreen(person: teacher)),
    );
    if (updated == null || !mounted) return;
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<AppUser>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final teachers = snapshot.data!;
          if (teachers.isEmpty) {
            return const Center(child: Text('No teachers yet.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: teachers.length,
            itemBuilder: (context, i) {
              final teacher = teachers[i];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(teacher.name),
                subtitle: Text(teacher.phone.isEmpty ? 'No phone on file' : teacher.phone),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openDetail(teacher),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addTeacher,
        tooltip: 'Invite a teacher',
        child: const Icon(Icons.person_add_alt_1_outlined),
      ),
    );
  }
}
