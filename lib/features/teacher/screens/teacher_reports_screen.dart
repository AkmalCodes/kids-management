import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/models/child.dart';
import '../../../core/services/child_service.dart';
import '../../../shared/widgets/signed_avatar.dart';
import 'daily_report_edit_screen.dart';

// Teacher's Reports tab: their class as a list; tap a child to write/edit
// that child's daily report for today.
class TeacherReportsScreen extends ConsumerStatefulWidget {
  const TeacherReportsScreen({super.key});

  @override
  ConsumerState<TeacherReportsScreen> createState() => _TeacherReportsScreenState();
}

class _TeacherReportsScreenState extends ConsumerState<TeacherReportsScreen> {
  late Future<List<Child>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Child>> _load() async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return [];
    return ref.read(childServiceProvider).fetchForTeacher(user.id);
  }

  Future<void> _openEditor(Child child) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DailyReportEditScreen(child: child)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Child>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final children = snapshot.data!;
        if (children.isEmpty) {
          return const Center(child: Text('No children assigned to you yet.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: children.length,
          itemBuilder: (context, i) {
            final child = children[i];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: ListTile(
                leading: SignedAvatar(
                  urlProvider: child.avatarPath == null
                      ? null
                      : signedChildAvatarUrlProvider(child.avatarPath!),
                  radius: 20,
                ),
                title: Text(child.name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openEditor(child),
              ),
            );
          },
        );
      },
    );
  }
}
