import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/models/child.dart';
import '../../../core/controllers/child_controller.dart';
import '../../../shared/util/date_display.dart';
import '../../../shared/widgets/signed_avatar.dart';
import 'daily_report_edit_screen.dart';
import '../../../shared/widgets/app_loader.dart';
import '../../../shared/widgets/refreshable_message.dart';

// Teacher's Reports tab: their class as a list. Pick a day (‹ › or the date
// picker) and search a student by name (collapsible), then tap a child to
// write/edit that child's report for the selected day.
class TeacherReportsScreen extends ConsumerStatefulWidget {
  const TeacherReportsScreen({super.key});

  @override
  ConsumerState<TeacherReportsScreen> createState() => _TeacherReportsScreenState();
}

class _TeacherReportsScreenState extends ConsumerState<TeacherReportsScreen> {
  late Future<List<Child>> _future;
  DateTime _date = DateTime.now();
  String _query = '';
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Child>> _load() async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return [];
    return ref.read(childControllerProvider).fetchForTeacher(user.id);
  }

  // Pull-to-refresh. Tab pages are kept alive (LazyIndexedStack), so this is
  // how the user picks up changes made elsewhere. FutureBuilder keeps showing
  // the old list while the new future runs, so there's no loader flash.
  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _future = next;
    });
    await next;
  }

  String get _iso => _date.toIso8601String().substring(0, 10);

  void _shiftDay(int days) => setState(() => _date = _date.add(Duration(days: days)));

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(DateTime.now().year - 2),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _openEditor(Child child) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DailyReportEditScreen(child: child, date: _iso)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Day selector + collapsible name search.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous day',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _shiftDay(-1),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: _pickDate,
                      child: Text(isoWithWeekday(_iso)),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next day',
                    icon: const Icon(Icons.chevron_right),
                    // Don't allow navigating into the future.
                    onPressed: _iso == DateTime.now().toIso8601String().substring(0, 10)
                        ? null
                        : () => _shiftDay(1),
                  ),
                  IconButton(
                    tooltip: 'Search students',
                    icon: Icon(_showSearch ? Icons.search_off : Icons.search),
                    onPressed: () => setState(() {
                      _showSearch = !_showSearch;
                      if (!_showSearch) _query = '';
                    }),
                  ),
                ],
              ),
              if (_showSearch)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search student name',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: FutureBuilder<List<Child>>(
              future: _future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: AppLoader());
                }
                final children = snapshot.data!
                    .where((c) => _query.isEmpty || c.name.toLowerCase().contains(_query))
                    .toList();
                if (children.isEmpty) {
                  return RefreshableMessage(_query.isEmpty
                      ? 'No children assigned to you yet.'
                      : 'No students match "$_query".');
                }
                return ListView.builder(
                  // Scrollable even when short, so it can be pulled to refresh.
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
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
                        onTap: () => _openEditor(child),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
