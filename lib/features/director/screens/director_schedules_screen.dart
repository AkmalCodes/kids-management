import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/app_user.dart';
import '../../../core/services/profile_service.dart';
import '../../../core/services/teacher_service.dart';
import '../../../shared/widgets/signed_avatar.dart';
import 'person_schedule_screen.dart';

// Director's "Schedules" tab: search/pick a teacher, land on their agenda
// view in edit mode. Director-managed child schedules aren't exposed here
// -- teachers are the actual use case, and this stays scannable as the
// teacher roster grows (hence the inline search instead of a full list).
class DirectorSchedulesScreen extends StatefulWidget {
  const DirectorSchedulesScreen({super.key});

  @override
  State<DirectorSchedulesScreen> createState() => _DirectorSchedulesScreenState();
}

class _DirectorSchedulesScreenState extends State<DirectorSchedulesScreen> {
  bool _searching = false;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchController.clear();
        _query = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: _searching
                    ? TextField(
                        controller: _searchController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'Search teachers…',
                          border: InputBorder.none,
                        ),
                        onChanged: (value) => setState(() => _query = value),
                      )
                    : Text(
                        'Teachers',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
              ),
              IconButton(
                icon: Icon(_searching ? Icons.close : Icons.search),
                tooltip: _searching ? 'Close search' : 'Search teachers',
                onPressed: _toggleSearch,
              ),
            ],
          ),
        ),
        Expanded(child: _TeacherList(query: _query)),
      ],
    );
  }
}

class _TeacherList extends ConsumerWidget {
  const _TeacherList({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<AppUser>>(
      future: ref.read(teacherServiceProvider).fetchAll(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final teachers = snapshot.data!
            .where((t) => t.name.toLowerCase().contains(query.toLowerCase()))
            .toList();
        if (teachers.isEmpty) {
          return Center(
            child: Text(query.isEmpty ? 'No teachers yet.' : 'No teachers match "$query".'),
          );
        }
        return ListView.builder(
          itemCount: teachers.length,
          itemBuilder: (context, i) {
            final teacher = teachers[i];
            return ListTile(
              leading: SignedAvatar(
                urlProvider: teacher.avatarPath == null
                    ? null
                    : signedAvatarUrlProvider(teacher.avatarPath!),
                radius: 20,
              ),
              title: Text(teacher.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PersonScheduleScreen(
                    title: teacher.name,
                    type: 'teacher',
                    refId: teacher.id,
                    centerId: teacher.centerId,
                    avatarPath: teacher.avatarPath,
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
