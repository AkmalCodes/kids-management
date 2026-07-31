import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/models/lesson_plan.dart';
import '../../../core/services/lesson_plan_service.dart';
import '../../../core/services/subject_service.dart';
import '../../../shared/util/date_display.dart';
import '../../../shared/widgets/lesson_plan_status_chip.dart';
import '../../shared_lessons/lesson_plan_edit_screen.dart';

// Teacher's Lessons tab: their own lesson plans (newest first) with the
// approval status, plus a + to write a new one. Tapping a plan opens the
// editor (edit while draft/rejected, submit for approval, delete).
class TeacherLessonPlansScreen extends ConsumerStatefulWidget {
  const TeacherLessonPlansScreen({super.key});

  @override
  ConsumerState<TeacherLessonPlansScreen> createState() => _TeacherLessonPlansScreenState();
}

class _PlansData {
  const _PlansData({required this.plans, required this.subjectsById});
  final List<LessonPlan> plans;
  final Map<String, String> subjectsById; // subject id -> name
}

class _TeacherLessonPlansScreenState extends ConsumerState<TeacherLessonPlansScreen> {
  late Future<_PlansData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_PlansData> _load() async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return const _PlansData(plans: [], subjectsById: {});
    final plans = await ref.read(lessonPlanServiceProvider).fetchForTeacher(user.id);
    final subjects = await ref.read(subjectServiceProvider).fetchAll();
    return _PlansData(
      plans: plans,
      subjectsById: {for (final s in subjects) s.id: s.name},
    );
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _open({LessonPlan? plan}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LessonPlanEditScreen(plan: plan, isDirector: false),
      ),
    );
    if (changed == true && mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<_PlansData>(
        future: _future,
        builder: (context, snapshot) {
          // Surface load errors instead of spinning forever (e.g. the
          // subjects/lesson_plans migration hasn't been run yet).
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
          if (data.plans.isEmpty) {
            return const Center(child: Text('No lesson plans yet.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: data.plans.length,
            itemBuilder: (context, i) {
              final plan = data.plans[i];
              final subject = plan.subjectId == null
                  ? null
                  : data.subjectsById[plan.subjectId];
              return ListTile(
                title: Text(plan.title),
                subtitle: Text(
                  subject == null
                      ? isoWithWeekday(plan.date)
                      : '${isoWithWeekday(plan.date)} · $subject',
                ),
                trailing: LessonPlanStatusChip(status: plan.status),
                onTap: () => _open(plan: plan),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _open(),
        tooltip: 'New lesson plan',
        child: const Icon(Icons.add),
      ),
    );
  }
}
