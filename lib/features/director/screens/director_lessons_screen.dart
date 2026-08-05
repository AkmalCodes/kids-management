import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/lesson_plan.dart';
import '../../../core/services/lesson_plan_service.dart';
import '../../../core/services/subject_service.dart';
import '../../../core/services/teacher_service.dart';
import '../../../shared/widgets/lesson_plan_status_chip.dart';
import '../../../shared/widgets/row_actions_sheet.dart';
import '../../shared_lessons/lesson_plan_edit_screen.dart';
import 'manage_subjects_screen.dart';

// Director's Lessons tab: browse every teacher's lesson plans, filter by
// teacher and approval status, and open one to approve/reject/edit. A Subjects
// button leads to the subject-management screen.
class DirectorLessonsScreen extends ConsumerStatefulWidget {
  const DirectorLessonsScreen({super.key});

  @override
  ConsumerState<DirectorLessonsScreen> createState() => _DirectorLessonsScreenState();
}

class _LessonsData {
  const _LessonsData({
    required this.plans,
    required this.teachersById,
    required this.subjectsById,
  });
  final List<LessonPlan> plans;
  final Map<String, String> teachersById;
  final Map<String, String> subjectsById;
}

class _DirectorLessonsScreenState extends ConsumerState<DirectorLessonsScreen> {
  late Future<_LessonsData> _future;
  String? _teacherFilter; // null = all teachers
  // Directors land on the review queue (plans awaiting approval); they can
  // switch the filter to see approved/rejected history.
  LessonPlanStatus? _statusFilter = LessonPlanStatus.submitted;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_LessonsData> _load() async {
    final plans = await ref.read(lessonPlanServiceProvider).fetchAll();
    final teachers = await ref.read(teacherServiceProvider).fetchAll();
    final subjects = await ref.read(subjectServiceProvider).fetchAll();
    return _LessonsData(
      plans: plans,
      teachersById: {for (final t in teachers) t.id: t.name},
      subjectsById: {for (final s in subjects) s.id: s.name},
    );
  }

  // Block body, not `() =>`: an arrow would return the Future from the
  // assignment and setState rejects a callback that returns a Future.
  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _open(LessonPlan plan) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LessonPlanEditScreen(plan: plan, isDirector: true),
      ),
    );
    if (changed == true && mounted) _refresh();
  }

  Future<void> _delete(LessonPlan plan) async {
    if (!await confirmDelete(context, message: 'Delete lesson plan "${plan.title}"?')) return;
    try {
      await ref.read(lessonPlanServiceProvider).deletePlan(plan.id);
      if (mounted) _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not delete: $e')));
      }
    }
  }

  Future<void> _openSubjects() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ManageSubjectsScreen()),
    );
  }

  List<LessonPlan> _applyFilters(List<LessonPlan> plans) {
    return plans.where((p) {
      if (_teacherFilter != null && p.teacherId != _teacherFilter) return false;
      if (_statusFilter != null && p.status != _statusFilter) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_LessonsData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load lesson plans:\n${snapshot.error}',
                  textAlign: TextAlign.center),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        final filtered = _applyFilters(data.plans);
        return Column(
          children: [
            _FilterBar(
              teachersById: data.teachersById,
              teacherFilter: _teacherFilter,
              statusFilter: _statusFilter,
              onTeacher: (v) => setState(() => _teacherFilter = v),
              onStatus: (v) => setState(() => _statusFilter = v),
              onSubjects: _openSubjects,
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('No lesson plans match.'))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final plan = filtered[i];
                        final teacher = data.teachersById[plan.teacherId] ?? 'Unknown teacher';
                        final subject = plan.subjectId == null
                            ? null
                            : data.subjectsById[plan.subjectId];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: ListTile(
                            title: Text(plan.title),
                            subtitle: Text(
                              '$teacher${subject == null ? '' : ' · $subject'}',
                            ),
                            trailing: LessonPlanStatusChip(status: plan.status),
                            onTap: () => _open(plan),
                            onLongPress: () => showRowActionsSheet(
                              context,
                              title: plan.title,
                              onEdit: () => _open(plan),
                              onDelete: () => _delete(plan),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.teachersById,
    required this.teacherFilter,
    required this.statusFilter,
    required this.onTeacher,
    required this.onStatus,
    required this.onSubjects,
  });

  final Map<String, String> teachersById;
  final String? teacherFilter;
  final LessonPlanStatus? statusFilter;
  final ValueChanged<String?> onTeacher;
  final ValueChanged<LessonPlanStatus?> onStatus;
  final VoidCallback onSubjects;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: teacherFilter,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(16),
                  decoration: const InputDecoration(labelText: 'Teacher', isDense: true),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All teachers')),
                    for (final entry in teachersById.entries)
                      DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                  ],
                  onChanged: onTeacher,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<LessonPlanStatus?>(
                  initialValue: statusFilter,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(16),
                  decoration: const InputDecoration(labelText: 'Status', isDense: true),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All statuses')),
                    DropdownMenuItem(
                        value: LessonPlanStatus.submitted, child: Text('Awaiting approval')),
                    DropdownMenuItem(value: LessonPlanStatus.approved, child: Text('Approved')),
                    DropdownMenuItem(value: LessonPlanStatus.rejected, child: Text('Rejected')),
                    DropdownMenuItem(value: LessonPlanStatus.draft, child: Text('Draft')),
                  ],
                  onChanged: onStatus,
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onSubjects,
              icon: const Icon(Icons.category_outlined),
              label: const Text('Subjects'),
            ),
          ),
        ],
      ),
    );
  }
}
