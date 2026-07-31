import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_service.dart';
import '../../core/models/class_group.dart';
import '../../core/models/lesson_plan.dart';
import '../../core/models/subject.dart';
import '../../core/services/class_service.dart';
import '../../core/services/lesson_plan_service.dart';
import '../../core/services/subject_service.dart';
import '../../shared/widgets/editable_field.dart';
import '../../shared/widgets/lesson_plan_status_chip.dart';

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
  late String _date; // YYYY-MM-DD
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
    _date = p?.date ?? DateTime.now().toIso8601String().substring(0, 10);
    _subjectId = p?.subjectId;
    _classId = p?.classId;
    _status = p?.status ?? LessonPlanStatus.draft;
    _subjectsFuture = ref.read(subjectServiceProvider).fetchAll();
    _classesFuture = ref.read(classServiceProvider).fetchAll();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  String _formatDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Future<void> _pickDate() async {
    final current = DateTime.tryParse(_date) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (picked != null) {
      setState(() => _date = picked.toIso8601String().substring(0, 10));
    }
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
    final service = ref.read(lessonPlanServiceProvider);
    await _run(() async {
      if (_isNew) {
        if (user.centerId == null) return;
        await service.createPlan(
          title: _titleController.text.trim(),
          date: _date,
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
          date: _date,
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
    final service = ref.read(lessonPlanServiceProvider);
    await _run(() async {
      await service.updatePlan(
        id: widget.plan!.id,
        title: _titleController.text.trim(),
        date: _date,
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
    final service = ref.read(lessonPlanServiceProvider);
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
    await _run(() => ref.read(lessonPlanServiceProvider).deletePlan(widget.plan!.id));
  }

  Widget _readOnlyRow(String label, String value) {
    final theme = Theme.of(context);
    final hasValue = value.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor)),
          const SizedBox(height: 2),
          Text(
            hasValue ? value : 'Not set',
            style: hasValue
                ? theme.textTheme.bodyLarge
                : theme.textTheme.bodyLarge?.copyWith(color: theme.disabledColor),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editable = _canEdit;
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? 'New lesson plan' : 'Lesson plan')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: LessonPlanStatusChip(status: _status),
            ),
            // A director's note on a rejected plan, so the teacher sees why.
            if (widget.plan?.reviewNote != null && widget.plan!.reviewNote!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Reviewer note', style: Theme.of(context).textTheme.labelSmall),
              Text(widget.plan!.reviewNote!),
            ],
            const SizedBox(height: 8),
            EditableField(
              label: 'Title',
              controller: _titleController,
              editing: editable,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a title' : null,
            ),
            // Date: picker when editable, plain row otherwise.
            if (editable)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event_outlined),
                  label: Text('Date: ${_formatDate(_date)}'),
                ),
              )
            else
              _readOnlyRow('Date', _formatDate(_date)),
            // Subject: dropdown when editable, resolved name otherwise.
            FutureBuilder<List<Subject>>(
              future: _subjectsFuture,
              builder: (context, snapshot) {
                final subjects = snapshot.data ?? [];
                if (!editable) {
                  var name = 'None';
                  if (_subjectId != null) {
                    name = '…';
                    for (final s in subjects) {
                      if (s.id == _subjectId) name = s.name;
                    }
                  }
                  return _readOnlyRow('Subject', name);
                }
                final ids = subjects.map((s) => s.id).toSet();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: DropdownButtonFormField<String?>(
                    initialValue:
                        (_subjectId != null && ids.contains(_subjectId)) ? _subjectId : null,
                    decoration: const InputDecoration(labelText: 'Subject'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None')),
                      for (final s in subjects)
                        DropdownMenuItem(value: s.id, child: Text(s.name)),
                    ],
                    onChanged: (v) => setState(() => _subjectId = v),
                  ),
                );
              },
            ),
            // Class: dropdown when editable, resolved name otherwise.
            FutureBuilder<List<ClassGroup>>(
              future: _classesFuture,
              builder: (context, snapshot) {
                final classes = snapshot.data ?? [];
                if (!editable) {
                  var name = 'None';
                  if (_classId != null) {
                    name = '…';
                    for (final c in classes) {
                      if (c.id == _classId) name = c.name;
                    }
                  }
                  return _readOnlyRow('Class', name);
                }
                final ids = classes.map((c) => c.id).toSet();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: DropdownButtonFormField<String?>(
                    initialValue: (_classId != null && ids.contains(_classId)) ? _classId : null,
                    decoration: const InputDecoration(labelText: 'Class'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None')),
                      for (final c in classes)
                        DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() => _classId = v),
                  ),
                );
              },
            ),
            EditableField(
              label: 'Content',
              controller: _contentController,
              editing: editable,
              maxLines: 6,
            ),
            const SizedBox(height: 24),
            ..._actions(editable),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(bool editable) {
    if (_saving) {
      return const [Center(child: CircularProgressIndicator())];
    }
    final buttons = <Widget>[];
    if (editable) {
      buttons.add(FilledButton(onPressed: _save, child: const Text('Save')));
    }
    // Teacher can submit a draft/rejected plan that already exists.
    if (!widget.isDirector &&
        !_isNew &&
        (_status == LessonPlanStatus.draft || _status == LessonPlanStatus.rejected)) {
      buttons.add(const SizedBox(height: 8));
      buttons.add(OutlinedButton(onPressed: _submit, child: const Text('Submit for approval')));
    }
    // Director reviews a submitted plan.
    if (widget.isDirector && _status == LessonPlanStatus.submitted) {
      buttons.add(const SizedBox(height: 8));
      buttons.add(Row(
        children: [
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () => _review(true),
              child: const Text('Approve'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: () => _review(false),
              child: const Text('Reject'),
            ),
          ),
        ],
      ));
    }
    // Delete: teacher on own, director on any (an existing plan).
    if (!_isNew) {
      buttons.add(const SizedBox(height: 8));
      buttons.add(TextButton.icon(
        onPressed: _delete,
        icon: const Icon(Icons.delete_outline, color: Colors.red),
        label: const Text('Delete', style: TextStyle(color: Colors.red)),
      ));
    }
    return buttons;
  }
}
