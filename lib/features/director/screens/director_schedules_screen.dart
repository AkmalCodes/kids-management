import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/class_group.dart';
import '../../../core/controllers/class_controller.dart';
import 'person_schedule_screen.dart';

// Director's "Schedules" tab: search/pick a class, land on its schedule in
// edit mode. Schedules belong to a class (§6.8), not an individual teacher.
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
                          hintText: 'Search classes…',
                          border: InputBorder.none,
                        ),
                        onChanged: (value) => setState(() => _query = value),
                      )
                    : Text(
                        'Classes',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
              ),
              IconButton(
                icon: Icon(_searching ? Icons.close : Icons.search),
                tooltip: _searching ? 'Close search' : 'Search classes',
                onPressed: _toggleSearch,
              ),
            ],
          ),
        ),
        Expanded(child: _ClassList(query: _query)),
      ],
    );
  }
}

class _ClassList extends ConsumerWidget {
  const _ClassList({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<ClassGroup>>(
      future: ref.read(classControllerProvider).fetchAll(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final classes = snapshot.data!
            .where((c) => c.name.toLowerCase().contains(query.toLowerCase()))
            .toList();
        if (classes.isEmpty) {
          return Center(
            child: Text(query.isEmpty ? 'No classes yet.' : 'No classes match "$query".'),
          );
        }
        return ListView.builder(
          itemCount: classes.length,
          itemBuilder: (context, i) {
            final classGroup = classes[i];
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.groups_outlined)),
              title: Text(classGroup.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PersonScheduleScreen(
                    title: classGroup.name,
                    type: 'class',
                    refId: classGroup.id,
                    centerId: classGroup.centerId,
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
