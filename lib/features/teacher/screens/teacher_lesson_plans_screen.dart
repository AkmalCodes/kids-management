import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/models/lesson_plan.dart';
import '../../../core/controllers/class_controller.dart';
import '../../../core/controllers/lesson_plan_controller.dart';
import '../../../core/controllers/subject_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/lesson_plan_status_chip.dart';
import '../../../shared/widgets/row_actions_sheet.dart';
import '../../../shared/widgets/subject_tile.dart';
import '../../shared_lessons/lesson_plan_edit_screen.dart';
import '../../../shared/widgets/app_loader.dart';

// Teacher's Lessons tab, laid out as screen design A1 "Calm workspace"
// (Figma page "Screen designs"):
//   - a greeting, so the tab feels like the teacher's workspace rather than
//     an admin table;
//   - two summary cards: how many plans, how many need the teacher, how many
//     are approved;
//   - one card per plan: subject tile, title, "subject · class", status, and
//     for a plan sent back by the director, their feedback with an Edit
//     shortcut;
//   - a labelled "Create lesson plan" button pinned above the nav bar.
// Lesson plans have no date in the data model, so cards don't show one.
// Tapping a plan opens the editor (edit while draft/needs changes, submit,
// delete); long-press offers Edit/Delete.
class TeacherLessonPlansScreen extends ConsumerStatefulWidget {
  const TeacherLessonPlansScreen({super.key});

  @override
  ConsumerState<TeacherLessonPlansScreen> createState() => _TeacherLessonPlansScreenState();
}

class _PlansData {
  const _PlansData({
    required this.userName,
    required this.plans,
    required this.subjectsById,
    required this.classesById,
  });
  final String userName;
  final List<LessonPlan> plans;
  final Map<String, String> subjectsById; // subject id -> name
  final Map<String, String> classesById; // class id -> name
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
    if (user == null) {
      return const _PlansData(userName: '', plans: [], subjectsById: {}, classesById: {});
    }
    final plans = await ref.read(lessonPlanControllerProvider).fetchForTeacher(user.id);
    final subjects = await ref.read(subjectControllerProvider).fetchAll();
    final classes = await ref.read(classControllerProvider).fetchAll();
    return _PlansData(
      userName: user.name,
      plans: plans,
      subjectsById: {for (final s in subjects) s.id: s.name},
      classesById: {for (final c in classes) c.id: c.name},
    );
  }

  // Block body, not `() =>`: an arrow would return the Future from the
  // assignment and setState rejects a callback that returns a Future.
  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  // Pull-to-refresh. Tab pages are kept alive (LazyIndexedStack), so this is
  // how the user picks up changes made elsewhere (e.g. the director approving
  // a plan). RefreshIndicator needs a Future to know when to hide its spinner.
  Future<void> _pullRefresh() async {
    final next = _load();
    setState(() {
      _future = next;
    });
    await next;
  }

  Future<void> _open({LessonPlan? plan}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LessonPlanEditScreen(plan: plan, isDirector: false),
      ),
    );
    if (changed == true && mounted) _refresh();
  }

  Future<void> _delete(LessonPlan plan) async {
    if (!await confirmDelete(context, message: 'Delete lesson plan "${plan.title}"?')) return;
    try {
      await ref.read(lessonPlanControllerProvider).deletePlan(plan.id);
      if (mounted) _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not delete: $e')));
      }
    }
  }

  // Time-of-day greeting, from the phone's clock.
  static String _greeting(String name) {
    final hour = DateTime.now().hour;
    final part = hour < 12 ? 'Good morning' : (hour < 18 ? 'Good afternoon' : 'Good evening');
    return name.isEmpty ? '$part!' : '$part, $name';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _pullRefresh,
        child: FutureBuilder<_PlansData>(
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
              return const Center(child: AppLoader());
            }
            return _buildContent(snapshot.data!);
          },
        ),
      ),
      // Inside this tab's own Scaffold, `bottomNavigationBar` sits just above
      // the shell's nav bar, so the main action is always in reach without
      // floating over the cards like the old + button did.
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: FilledButton.icon(
          onPressed: () => _open(),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.onAccent,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Create lesson plan'),
        ),
      ),
    );
  }

  Widget _buildContent(_PlansData data) {
    final plans = data.plans;
    // "Needs attention" = plans waiting on the teacher: unfinished drafts and
    // ones the director sent back.
    final needAttention = plans
        .where((p) => p.status == LessonPlanStatus.draft || p.status == LessonPlanStatus.rejected)
        .length;
    final approved = plans.where((p) => p.status == LessonPlanStatus.approved).length;
    final (_, amber) = LessonPlanStatusChip.colorsFor(LessonPlanStatus.submitted);
    final (_, green) = LessonPlanStatusChip.colorsFor(LessonPlanStatus.approved);

    return ListView(
      // Always scrollable, even when short, so pull-to-refresh still works.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        Text(
          _greeting(data.userName),
          style: const TextStyle(
              fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.onAccent),
        ),
        const SizedBox(height: 2),
        const Text(
          "Let's make today a great learning day.",
          style: TextStyle(fontSize: 14, color: AppTheme.bodyText),
        ),
        const SizedBox(height: 16),
        // IntrinsicHeight makes both cards as tall as the taller one.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _StatCard(
                  value: plans.length,
                  label: 'Lesson plans',
                  hint: needAttention > 0 ? '$needAttention need attention' : 'All caught up',
                  hintColor: needAttention > 0 ? amber : green,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  value: approved,
                  label: 'Approved',
                  hint: 'Ready to teach',
                  hintColor: green,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'Your lesson plans',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.onAccent),
        ),
        const SizedBox(height: 10),
        if (plans.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                Text('No lesson plans yet.',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.onAccent)),
                SizedBox(height: 4),
                Text('Tap "Create lesson plan" to write your first one.',
                    style: TextStyle(color: AppTheme.bodyText)),
              ],
            ),
          ),
        for (final plan in plans)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _PlanCard(
              plan: plan,
              subjectName: plan.subjectId == null ? null : data.subjectsById[plan.subjectId],
              className: plan.classId == null ? null : data.classesById[plan.classId],
              onTap: () => _open(plan: plan),
              onLongPress: () => showRowActionsSheet(
                context,
                title: plan.title,
                onEdit: () => _open(plan: plan),
                onDelete: () => _delete(plan),
              ),
            ),
          ),
      ],
    );
  }
}

// One summary number ("8 · Lesson plans · 2 need attention").
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    required this.hint,
    required this.hintColor,
  });

  final int value;
  final String label;
  final String hint;
  final Color hintColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value',
              style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.onAccent)),
          Text(label,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.bodyText)),
          Text(hint,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: hintColor)),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.subjectName,
    required this.className,
    required this.onTap,
    required this.onLongPress,
  });

  final LessonPlan plan;
  final String? subjectName;
  final String? className;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    // whereType<String> drops the nulls: "Arts · Class A", "Arts", or "".
    final meta = [subjectName, className].whereType<String>().join(' · ');
    final note = plan.reviewNote?.trim() ?? '';
    final showFeedback = plan.status == LessonPlanStatus.rejected && note.isNotEmpty;
    final (feedbackBg, feedbackFg) = LessonPlanStatusChip.colorsFor(LessonPlanStatus.rejected);

    // Material + InkWell (not a plain Container) so taps get the ripple, and
    // clipBehavior keeps that ripple inside the rounded corners.
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.hairline),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SubjectTile(name: subjectName),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(plan.title,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.onAccent)),
                        const SizedBox(height: 2),
                        Text(meta.isEmpty ? 'No subject or class yet' : meta,
                            style: const TextStyle(fontSize: 12, color: AppTheme.bodyText)),
                        const SizedBox(height: 6),
                        LessonPlanStatusChip(status: plan.status),
                      ],
                    ),
                  ),
                ],
              ),
              // The director's reason, right on the card, so the teacher
              // knows what to fix before even opening the plan. The whole card
              // is tappable, so "Edit" just labels what a tap does.
              if (showFeedback) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  decoration: BoxDecoration(
                    color: feedbackBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Feedback: $note',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600, color: feedbackFg)),
                      ),
                      const SizedBox(width: 8),
                      Text('Edit',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800, color: feedbackFg)),
                      Icon(Icons.arrow_forward, size: 14, color: feedbackFg),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
