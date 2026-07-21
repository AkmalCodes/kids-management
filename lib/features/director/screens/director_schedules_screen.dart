import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/child.dart';
import '../../../core/services/child_service.dart';
import '../../../core/services/teacher_service.dart';
import 'person_schedule_screen.dart';

// Director's "Schedules" tab: pick a teacher or a child, land on their
// agenda view in edit mode (any teacher's or child's schedule, per the
// schedule_entries RLS policies granting directors full access).
class DirectorSchedulesScreen extends StatelessWidget {
  const DirectorSchedulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const Material(
            child: TabBar(
              tabs: [Tab(text: 'Teachers'), Tab(text: 'Children')],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [_TeacherList(), _ChildList()],
            ),
          ),
        ],
      ),
    );
  }
}

class _TeacherList extends ConsumerWidget {
  const _TeacherList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<AppUser>>(
      future: ref.read(teacherServiceProvider).fetchAll(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final teachers = snapshot.data!;
        if (teachers.isEmpty) {
          return const Center(child: Text('No teachers yet.'));
        }
        return ListView.builder(
          itemCount: teachers.length,
          itemBuilder: (context, i) {
            final teacher = teachers[i];
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(teacher.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PersonScheduleScreen(
                    title: teacher.name,
                    type: 'teacher',
                    refId: teacher.id,
                    centerId: teacher.centerId,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ChildList extends ConsumerWidget {
  const _ChildList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<Child>>(
      future: ref.read(childServiceProvider).fetchAll(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final children = snapshot.data!;
        if (children.isEmpty) {
          return const Center(child: Text('No children enrolled yet.'));
        }
        return ListView.builder(
          itemCount: children.length,
          itemBuilder: (context, i) {
            final child = children[i];
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.child_care_outlined)),
              title: Text(child.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PersonScheduleScreen(
                    title: child.name,
                    type: 'child',
                    refId: child.id,
                    centerId: child.centerId,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
