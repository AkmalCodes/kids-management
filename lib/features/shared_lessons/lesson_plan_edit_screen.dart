import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/class_group.dart';
import '../../core/models/lesson_plan.dart';
import '../../core/models/subject.dart';
import '../../core/controllers/class_controller.dart';
import '../../core/controllers/lesson_plan_controller.dart';
import '../../core/controllers/subject_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/lesson_plan_status_chip.dart';
import '../../shared/widgets/app_dropdown_field.dart';
import '../../shared/widgets/app_loader.dart';

// Create/edit/review one lesson plan. Shared by teachers and directors:
//  - Teacher (isDirector = false): creates a plan (draft), edits it while
//    draft/rejected, and submits it for approval. Once submitted/approved
//    the fields are read-only.
//  - Director (isDirector = true): edits any plan, and approves/rejects a
//    submitted one (with an optional note).
// Pops `true` on any successful change so the caller can refresh its list.
class LessonPlanEditScreen extends ConsumerStatefulWidget {
  const LessonPlanEditScreen({super.key, this.plan, required this.isDirector});

  // null = create a new plan (teacher flow only).
  final LessonPlan? plan;
  final bool isDirector;

  @override
  ConsumerState<LessonPlanEditScreen> createState() => _LessonPlanEditScreenState();
}

class _LessonPlanEditScreenState extends ConsumerState<LessonPlanEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late String? _subjectId;
  late String? _classId;
  late LessonPlanStatus _status;
  late Future<List<Subject>> _subjectsFuture;
  late Future<List<ClassGroup>> _classesFuture;
  bool _saving = false;

  bool get _isNew => widget.plan == null;

  // Teacher can edit while draft/rejected (or brand new); a director can edit
  // any plan; a submitted/approved plan is read-only to its teacher.
  bool get _canEdit =>
      widget.isDirector ||
      _isNew ||
      _status == LessonPlanStatus.draft ||
      _status == LessonPlanStatus.rejected;

  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    _titleController = TextEditingController(text: p?.title ?? '');
    _contentController = TextEditingController(text: p?.content ?? '');
    _subjectId = p?.subjectId;
    _classId = p?.classId;
    _status = p?.status ?? LessonPlanStatus.draft;
    _subjectsFuture = ref.read(subjectControllerProvider).fetchAll();
    _classesFuture = ref.read(classControllerProvider).fetchAll();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  // Runs an action with the saving spinner + standard error snackbar, and
  // pops `true` on success so the list refreshes.
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return;
    final service = ref.read(lessonPlanControllerProvider);
    await _run(() async {
      if (_isNew) {
        if (user.centerId == null) return;
        await service.createPlan(
          title: _titleController.text.trim(),
          content: _contentController.text.trim(),
          subjectId: _subjectId,
          classId: _classId,
          teacherId: user.id,
          centerId: user.centerId!,
          actorUid: user.id,
        );
      } else {
        await service.updatePlan(
          id: widget.plan!.id,
          title: _titleController.text.trim(),
          content: _contentController.text.trim(),
          subjectId: _subjectId,
          classId: _classId,
          actorUid: user.id,
        );
      }
    });
  }

  Future<void> _submit() async {
    // Persist edits first, then flip to submitted -- so what the director
    // reviews is exactly what's on screen.
    if (!_formKey.currentState!.validate()) return;
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return;
    final service = ref.read(lessonPlanControllerProvider);
    await _run(() async {
      await service.updatePlan(
        id: widget.plan!.id,
        title: _titleController.text.trim(),
        content: _contentController.text.trim(),
        subjectId: _subjectId,
        classId: _classId,
        actorUid: user.id,
      );
      await service.submitPlan(id: widget.plan!.id, actorUid: user.id);
    });
  }

  Future<void> _review(bool approved) async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return;
    final note = await _askReviewNote(approved);
    if (note == null) return; // cancelled
    final service = ref.read(lessonPlanControllerProvider);
    await _run(() => service.reviewPlan(
          id: widget.plan!.id,
          approved: approved,
          note: note.isEmpty ? null : note,
          actorUid: user.id,
        ));
  }

  // Returns the note (possibly empty) on confirm, or null on cancel.
  Future<String?> _askReviewNote(bool approved) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(approved ? 'Approve plan' : 'Reject plan'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: approved ? 'Note (optional)' : 'Reason (optional)',
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(approved ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete lesson plan?'),
        content: const Text('This permanently removes the plan.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => ref.read(lessonPlanControllerProvider).deletePlan(widget.plan!.id));
  }

  // Resolves an id to its display name once the list has loaded.
  static String _nameFor<T>(List<T> items, String? id, String Function(T) idOf,
      String Function(T) nameOf) {
    if (id == null) return 'None';
    for (final item in items) {
      if (idOf(item) == id) return nameOf(item);
    }
    return '…'; // still loading, or the row was deleted
  }

  Widget _subjectField(bool editable) {
    return FutureBuilder<List<Subject>>(
      future: _subjectsFuture,
      builder: (context, snapshot) {
        final subjects = snapshot.data ?? [];
        if (!editable) {
          return _Labeled(
            label: 'Subject',
            child: _ReadOnlyValue(_nameFor(subjects, _subjectId, (s) => s.id, (s) => s.name)),
          );
        }
        final ids = subjects.map((s) => s.id).toSet();
        return _Labeled(
          label: 'Subject',
          child: AppDropdownField<String?>(
            value: (_subjectId != null && ids.contains(_subjectId)) ? _subjectId : null,
            decoration: const InputDecoration(),
            items: [
              const DropdownMenuItem(value: null, child: Text('None')),
              for (final s in subjects) DropdownMenuItem(value: s.id, child: Text(s.name)),
            ],
            onChanged: (v) => setState(() => _subjectId = v),
          ),
        );
      },
    );
  }

  Widget _classField(bool editable) {
    return FutureBuilder<List<ClassGroup>>(
      future: _classesFuture,
      builder: (context, snapshot) {
        final classes = snapshot.data ?? [];
        if (!editable) {
          return _Labeled(
            label: 'Class',
            child: _ReadOnlyValue(_nameFor(classes, _classId, (c) => c.id, (c) => c.name)),
          );
        }
        final ids = classes.map((c) => c.id).toSet();
        return _Labeled(
          label: 'Class',
          child: AppDropdownField<String?>(
            value: (_classId != null && ids.contains(_classId)) ? _classId : null,
            decoration: const InputDecoration(),
            items: [
              const DropdownMenuItem(value: null, child: Text('None')),
              for (final c in classes) DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => _classId = v),
          ),
        );
      },
    );
  }

  // Layout follows screen design A2 "Calm workspace" (Figma page "Screen
  // designs"): status + delete in the app bar, the reviewer's feedback as a
  // banner, BASICS and CONTENT sections with labels above light fields, and
  // the actions pinned in a bottom bar so they're always in reach.
  @override
  Widget build(BuildContext context) {
    final editable = _canEdit;
    final note = widget.plan?.reviewNote?.trim() ?? '';
    // lightForm: white, thin-bordered fields and dark-rose buttons, for this
    // screen only (see AppTheme.lightForm).
    return Theme(
      data: AppTheme.lightForm(Theme.of(context)),
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? 'New lesson plan' : 'Lesson plan'),
          actions: [
            Center(child: LessonPlanStatusChip(status: _status)),
            // Delete: teacher on own, director on any (an existing plan).
            // Disabled while a save/review is in flight.
            if (!_isNew)
              IconButton(
                tooltip: 'Delete',
                color: Theme.of(context).colorScheme.error,
                icon: const Icon(Icons.delete_outline),
                onPressed: _saving ? null : _delete,
              )
            else
              const SizedBox(width: 12),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              // A director's note (usually the reason a plan needs changes),
              // first thing on the page so the teacher sees why.
              if (note.isNotEmpty) ...[
                _FeedbackBanner(note: note, status: _status),
                const SizedBox(height: 18),
              ],
              const _SectionLabel('BASICS'),
              const SizedBox(height: 10),
              _Labeled(
                label: 'Lesson title',
                child: editable
                    ? TextFormField(
                        key: const Key('lesson-title'),
                        controller: _titleController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration:
                            const InputDecoration(hintText: 'e.g. Learning about colours'),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Please enter a title' : null,
                      )
                    : _ReadOnlyValue(_titleController.text.trim()),
              ),
              const SizedBox(height: 14),
              // Subject and Class side by side: short values, related, and it
              // saves a whole row of height.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _subjectField(editable)),
                  const SizedBox(width: 10),
                  Expanded(child: _classField(editable)),
                ],
              ),
              const SizedBox(height: 22),
              const _SectionLabel('CONTENT'),
              const SizedBox(height: 10),
              _Labeled(
                label: 'Objectives & activities',
                child: editable
                    ? TextFormField(
                        key: const Key('lesson-content'),
                        controller: _contentController,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        minLines: 8,
                        maxLines: null, // grows with the text
                        decoration: const InputDecoration(
                          hintText: 'What will the children learn, and how?',
                        ),
                      )
                    : _ReadOnlyValue(_contentController.text.trim()),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _actionBar(editable),
      ),
    );
  }

  // The pinned bottom bar, or null when this viewer has nothing to do (a
  // teacher looking at their submitted/approved plan).
  Widget? _actionBar(bool editable) {
    final teacherCanSubmit = !widget.isDirector &&
        !_isNew &&
        (_status == LessonPlanStatus.draft || _status == LessonPlanStatus.rejected);
    final directorReviews = widget.isDirector && _status == LessonPlanStatus.submitted;
    if (!editable && !directorReviews) return null;

    final Widget content;
    if (_saving) {
      content = const SizedBox(height: 48, child: Center(child: AppLoader(delayed: false)));
    } else if (directorReviews) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Approve/Reject don't save edits, so a director who tweaked the
          // text saves first.
          TextButton(onPressed: _save, child: const Text('Save changes')),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                    onPressed: () => _review(false), child: const Text('Reject')),
              ),
              const SizedBox(width: 10),
              // No style override: colours come from the theme (lightForm).
              Expanded(
                child: FilledButton(onPressed: () => _review(true), child: const Text('Approve')),
              ),
            ],
          ),
        ],
      );
    } else if (teacherCanSubmit) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: _save, child: const Text('Save draft'))),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(onPressed: _submit, child: const Text('Submit')),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text("You can still edit it until it's approved.",
              style: TextStyle(fontSize: 11, color: AppTheme.mutedText)),
        ],
      );
    } else {
      // A brand-new plan (submit needs a saved plan first), or a director
      // editing a plan that isn't awaiting review.
      content = SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _save,
          child: Text(widget.isDirector ? 'Save changes' : 'Save draft'),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.hairline)),
        ),
        child: Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 12), child: content),
      ),
    );
  }
}

// Small spaced-out caps heading that groups the form ("BASICS").
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.9,
          color: AppTheme.mutedText,
        ),
      );
}

// A field label placed ABOVE its input. Material's default labelText floats
// inside the border and shrinks on focus; a fixed label above reads calmer
// and keeps the fields compact.
class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.onAccent)),
          const SizedBox(height: 6),
          child,
        ],
      );
}

// Read-only version of a field (a submitted/approved plan, viewed by its
// teacher): plain text where the input would be, "Not set" when empty.
class _ReadOnlyValue extends StatelessWidget {
  const _ReadOnlyValue(this.value);
  final String value;

  @override
  Widget build(BuildContext context) {
    final empty = value.isEmpty || value == 'None';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        empty ? 'Not set' : value,
        style: TextStyle(
          fontSize: 15,
          height: 1.45,
          color: empty ? AppTheme.mutedText : AppTheme.bodyText,
        ),
      ),
    );
  }
}

// The reviewer's note, tinted by the plan's status: red when it needs
// changes, green when approved, neutral otherwise.
class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({required this.note, required this.status});
  final String note;
  final LessonPlanStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      LessonPlanStatus.rejected || LessonPlanStatus.approved =>
        LessonPlanStatusChip.colorsFor(status),
      _ => (AppTheme.barTint, AppTheme.onAccent),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Feedback from reviewer',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: fg)),
          const SizedBox(height: 4),
          Text(note, style: TextStyle(fontSize: 13, height: 1.45, color: fg)),
        ],
      ),
    );
  }
}
