# Co-teachers on a Class Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A class can have zero, one, or many teachers, all with equal rights, via a `teacher_uids UUID[]` column on `classes` that replaces `teacher_uid`. A director assigns them with a shared multi-select widget, and a teacher can read a co-teacher's profile.

**Architecture:** One array column swap in the DB plus a six-spot RLS/function/storage rewrite (`teacher_uid = auth.uid()` → `auth.uid() = ANY(teacher_uids)`) and a new `shares_class_with()` helper widening `profiles_select`. In Dart, `ClassGroup.teacherId` (`String?`) becomes `teacherIds` (`List<String>`); a temporary `teacherId` getter bridges the rename across tasks. A new `TeacherMultiSelect` widget replaces the single-teacher dropdowns in the create dialog and the class detail screen.

**Tech Stack:** PostgreSQL/Supabase (RLS, no automated policy suite — verified by hand), Flutter, Riverpod 2.x, mocktail.

**Spec:** `docs/superpowers/specs/2026-09-04-co-teachers-design.md`

## Global Constraints

- Piece **B** of three (A: grid tile label — shipped; C: two-grid attendance page — later). This plan does **not** build the attendance page. It does add `TeacherController.fetchCoTeachers` (Task 6) so B is independently complete.
- `children.teacher_id` is a separate, direct column and is **never** touched. Which children a teacher sees for attendance / daily reports does not change. A child still has exactly one assigned teacher.
- No "lead" / "primary" teacher. All ids in `teacher_uids` are equal. `teacher_uid` is dropped, not demoted.
- `schedule_entries` `update` / `delete` policies (`created_by`-based) are **not** touched — a co-teacher edits only entries they created, exactly as the single teacher does today. Only `schedule_entries_select` and `_insert` (their `type='class'` branches) change.
- Exhaustive list of the six `classes.teacher_uid = auth.uid()` references to rewrite, all in `docs/superpowers/specs/2026-08-07-security-hardening.sql`: `schedule_entries_select`, `schedule_entries_insert`, `lesson_plans_select` (approved-teacher branch), `classes_select`, `class_plan_subjects(p_class_id)` SECURITY DEFINER function, `class_avatars_select` storage policy. Each becomes `auth.uid() = ANY(<classes alias>.teacher_uids)`.
- New helper `shares_class_with(target uuid)` is `LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''` with schema-qualified names — matching every other helper in the hardening SQL.
- Migration SQL order is fixed: add column → backfill → create helper+trigger → `CREATE OR REPLACE` all rewritten policies/function + new `profiles_select` → **`DROP COLUMN teacher_uid` last**. Dropping it earlier makes every rewritten policy error and breaks the app for all roles.
- No dedicated unit-test file for `ClassController` or `TeacherController` — repo convention for Supabase-backed controllers (verified: no `attendance_controller_test.dart`, `class_controller_test.dart`, etc.). Their contracts are proven through the widget tests that consume them; `flutter analyze` is their compile gate.
- The full Flutter suite must stay green. Report the real count from `flutter test` output.
- Do not add a `Co-Authored-By` trailer to commits (repo convention — every prior commit on this branch has none).

---

### Task 1: Migration SQL + manual verification walkthrough

No automated test loop — SQL applied by hand in the Supabase dashboard, per this project's established practice (see `docs/superpowers/specs/2026-09-02-staff-attendance-schema.md` Task 1). Deliverable: one ordered `.sql` file plus a walkthrough the user runs themselves.

**Files:**
- Create: `docs/superpowers/specs/2026-09-04-co-teachers.sql`

**Interfaces:**
- Consumes: the existing `classes.teacher_uid` column and the six policies/function listed in Global Constraints.
- Produces: `classes.teacher_uids UUID[] NOT NULL DEFAULT '{}'` (and no more `teacher_uid`); `shares_class_with(uuid)`; `remove_teacher_from_classes()` + `profiles_after_delete_clear_class_teacher` trigger; rewritten policies. Later tasks' `ClassGroup.fromJson` reads `teacher_uids`; `ClassController` filters with `.contains('teacher_uids', [...])`.

- [ ] **Step 1: Write the migration SQL**

Create `docs/superpowers/specs/2026-09-04-co-teachers.sql`:

```sql
-- Co-teachers on a class: replace classes.teacher_uid (one teacher) with
-- classes.teacher_uids UUID[] (many). See the design spec at
-- docs/superpowers/specs/2026-09-04-co-teachers-design.md for the full
-- reasoning, including why an array column was chosen over a junction table.
--
-- Run this ONCE, by hand, in the Supabase SQL editor (Project -> SQL Editor),
-- top to bottom. The order matters: the teacher_uid column is dropped only at
-- the very end, after every policy that referenced it has been rewritten.
-- Dropping it earlier makes those policies error and breaks the app.

-- 1. Add the array column. NOT NULL DEFAULT '{}' so it is always a real
--    (possibly empty) array -- callers never branch on null.
ALTER TABLE classes ADD COLUMN teacher_uids UUID[] NOT NULL DEFAULT '{}';

-- 2. Backfill: wrap each existing single teacher in a one-element array.
UPDATE classes SET teacher_uids = ARRAY[teacher_uid] WHERE teacher_uid IS NOT NULL;

-- 3. Helper: does the current user share a class with `target`? SECURITY
--    DEFINER so the classes lookup here is not itself re-filtered by classes
--    RLS. Mirrors the style of my_center() / current_role_name().
CREATE OR REPLACE FUNCTION shares_class_with(target UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.classes c
    WHERE auth.uid() = ANY(c.teacher_uids)
      AND target = ANY(c.teacher_uids)
  );
$$;

-- 4. Trigger: an array has no per-element FK, so deleting a teacher's profile
--    does not clear their id from teacher_uids. Do it here. Harmless if it
--    lingers (matches no auth.uid()), so this is tidiness, not security.
CREATE OR REPLACE FUNCTION remove_teacher_from_classes()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  UPDATE public.classes
     SET teacher_uids = array_remove(teacher_uids, OLD.id)
   WHERE OLD.id = ANY(teacher_uids);
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS profiles_after_delete_clear_class_teacher ON profiles;
CREATE TRIGGER profiles_after_delete_clear_class_teacher
  AFTER DELETE ON profiles
  FOR EACH ROW EXECUTE FUNCTION remove_teacher_from_classes();

-- 5. Rewrite every policy / function / storage policy that tested
--    "classes.teacher_uid = auth.uid()".

-- 5a. classes_select
DROP POLICY IF EXISTS "classes_select" ON classes;
CREATE POLICY "classes_select" ON classes FOR SELECT USING (
  (current_role_name() = 'director' AND center_id = my_center())
  OR auth.uid() = ANY(teacher_uids)
  OR EXISTS (SELECT 1 FROM children c JOIN children_parents cp ON cp.child_id = c.id
             WHERE c.class_id = classes.id AND cp.parent_id = auth.uid())
);

-- 5b. schedule_entries_select (only the type='class' teacher branch changes)
DROP POLICY IF EXISTS "schedule_entries_select" ON schedule_entries;
CREATE POLICY "schedule_entries_select" ON schedule_entries FOR SELECT USING (
  (current_role_name() = 'director' AND center_id = my_center())
  OR (type = 'teacher' AND current_role_name() = 'teacher')
  OR (type = 'child' AND EXISTS (
        SELECT 1 FROM children WHERE children.id = schedule_entries.ref_id AND children.teacher_id = auth.uid()))
  OR (type = 'child' AND EXISTS (
        SELECT 1 FROM children_parents WHERE children_parents.child_id = schedule_entries.ref_id AND children_parents.parent_id = auth.uid()))
  OR (type = 'class' AND EXISTS (
        SELECT 1 FROM classes WHERE classes.id = schedule_entries.ref_id AND auth.uid() = ANY(classes.teacher_uids)))
  OR (type = 'class' AND EXISTS (
        SELECT 1 FROM classes cl JOIN children c ON c.class_id = cl.id JOIN children_parents cp ON cp.child_id = c.id
        WHERE cl.id = schedule_entries.ref_id AND cp.parent_id = auth.uid()))
);

-- 5c. schedule_entries_insert (only the type='class' teacher branch changes)
DROP POLICY IF EXISTS "schedule_entries_insert" ON schedule_entries;
CREATE POLICY "schedule_entries_insert" ON schedule_entries FOR INSERT WITH CHECK (
  (current_role_name() = 'director' AND center_id = my_center())
  OR (current_role_name() = 'teacher' AND type = 'teacher' AND ref_id = auth.uid())
  OR (type = 'class' AND EXISTS (
        SELECT 1 FROM classes WHERE classes.id = schedule_entries.ref_id AND auth.uid() = ANY(classes.teacher_uids)))
);

-- 5d. lesson_plans_select (only the approved-teacher branch changes)
DROP POLICY IF EXISTS "lesson_plans_select" ON lesson_plans;
CREATE POLICY "lesson_plans_select" ON lesson_plans FOR SELECT USING (
  teacher_id = auth.uid()
  OR (current_role_name() = 'director' AND center_id = my_center())
  OR (status = 'approved' AND EXISTS (
        SELECT 1 FROM classes c WHERE c.id = lesson_plans.class_id AND auth.uid() = ANY(c.teacher_uids)))
  OR (status = 'approved' AND EXISTS (
        SELECT 1 FROM children ch JOIN children_parents cp ON cp.child_id = ch.id
        WHERE ch.class_id = lesson_plans.class_id AND cp.parent_id = auth.uid()))
);

-- 5e. class_plan_subjects() SECURITY DEFINER function
CREATE OR REPLACE FUNCTION class_plan_subjects(p_class_id UUID)
RETURNS TABLE (plan_id UUID, title TEXT, subject_name TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT lp.id, lp.title, s.name
  FROM public.lesson_plans lp
  LEFT JOIN public.subjects s ON s.id = lp.subject_id
  WHERE lp.class_id = p_class_id AND lp.status = 'approved'
    AND (
      public.current_role_name() = 'director'
      OR EXISTS (SELECT 1 FROM public.classes c WHERE c.id = p_class_id AND auth.uid() = ANY(c.teacher_uids))
      OR EXISTS (SELECT 1 FROM public.children ch JOIN public.children_parents cp ON cp.child_id = ch.id
                 WHERE ch.class_id = p_class_id AND cp.parent_id = auth.uid())
    );
$$;

-- 5f. class_avatars_select storage policy (only the teacher branch changes)
DROP POLICY IF EXISTS "class_avatars_select" ON storage.objects;
CREATE POLICY "class_avatars_select" ON storage.objects FOR SELECT USING (
  bucket_id = 'class-avatars' AND (
    (current_role_name() = 'director' AND EXISTS (
        SELECT 1 FROM classes WHERE classes.id::text = (storage.foldername(objects.name))[1] AND classes.center_id = my_center()))
    OR EXISTS (SELECT 1 FROM classes WHERE classes.id::text = (storage.foldername(objects.name))[1] AND auth.uid() = ANY(classes.teacher_uids))
    OR EXISTS (SELECT 1 FROM classes cl JOIN children c ON c.class_id = cl.id JOIN children_parents cp ON cp.child_id = c.id
               WHERE cl.id::text = (storage.foldername(objects.name))[1] AND cp.parent_id = auth.uid())
  )
);

-- 5g. profiles_select gains a co-teacher branch
DROP POLICY IF EXISTS "profiles_select" ON profiles;
CREATE POLICY "profiles_select" ON profiles FOR SELECT USING (
  id = auth.uid()
  OR (current_role_name() = 'director' AND center_id = my_center())
  OR shares_class_with(id)
);

-- 6. Finally: drop the old column. Nothing references it any more.
ALTER TABLE classes DROP COLUMN teacher_uid;
```

- [ ] **Step 2: Hand the user the file and dashboard steps**

Tell the user, in these words or close to them:

> Open the Supabase dashboard for project `rpefksoutqsbreiyppee` → **SQL Editor** → **New query**. Paste the whole contents of `docs/superpowers/specs/2026-09-04-co-teachers.sql` and click **Run**. It runs top to bottom in one go. Expect `Success. No rows returned.`

- [ ] **Step 3: Give the user a manual verification walkthrough**

Hand the user this sequence (they run it — "user drives" convention). Each block is a separate query. Between blocks, say what to look for.

```sql
-- 1. The column swap took.
select column_name, data_type from information_schema.columns
where table_name = 'classes' and column_name in ('teacher_uid', 'teacher_uids');
```
Expected: one row, `teacher_uids`, `ARRAY`. No `teacher_uid` row.

```sql
-- 2. Backfill preserved existing assignments.
select id, name, teacher_uids from classes order by name;
```
Expected: every class that had a teacher now has a one-element `teacher_uids`.

Find a class id, its current teacher's uuid, and a second teacher's uuid in the same center:
```sql
select p.id, p.name, p.role, p.center_id from profiles p where p.role = 'teacher' order by p.center_id, p.name;
```

```sql
-- 3. A teacher in teacher_uids can see the class, its class schedule, its
--    approved lesson plans. Impersonate them:
select set_config('request.jwt.claims',
  json_build_object('sub', '<teacher-in-array-uuid>', 'role', 'authenticated')::text, true);
select id, name from classes where id = '<class-id>';
select count(*) from schedule_entries where type = 'class' and ref_id = '<class-id>';
select count(*) from lesson_plans where class_id = '<class-id>' and status = 'approved';
```
Expected: the class row returns; the counts run without error.

```sql
-- 4. A teacher NOT in the array cannot see the class.
select set_config('request.jwt.claims',
  json_build_object('sub', '<other-teacher-uuid>', 'role', 'authenticated')::text, true);
select id, name from classes where id = '<class-id>';
```
Expected: zero rows.

```sql
-- 5. Add that second teacher to the array (as the service role) and re-check.
select set_config('request.jwt.claims', null, true);
update classes set teacher_uids = array_append(teacher_uids, '<other-teacher-uuid>') where id = '<class-id>';
select set_config('request.jwt.claims',
  json_build_object('sub', '<other-teacher-uuid>', 'role', 'authenticated')::text, true);
select id, name from classes where id = '<class-id>';
-- ...and now this teacher can read the first teacher's profile:
select id, name from profiles where id = '<teacher-in-array-uuid>';
```
Expected: the class row now returns for the second teacher; so does the first teacher's profile row.

```sql
-- 6. A teacher sharing NO class with them still can't read that profile.
select set_config('request.jwt.claims',
  json_build_object('sub', '<a-third-unrelated-teacher-uuid>', 'role', 'authenticated')::text, true);
select id, name from profiles where id = '<teacher-in-array-uuid>';
```
Expected: zero rows.

```sql
-- 7. Removing an id revokes access. (service role)
select set_config('request.jwt.claims', null, true);
update classes set teacher_uids = array_remove(teacher_uids, '<other-teacher-uuid>') where id = '<class-id>';
```

```sql
-- 8. The delete trigger clears a removed teacher. Only run against a
--    genuinely disposable test teacher account, or skip.
-- (service role) delete from profiles where id = '<disposable-teacher-uuid>';
-- select id, teacher_uids from classes where '<disposable-teacher-uuid>' = ANY(teacher_uids);  -- expect zero
```

- [ ] **Step 4: Confirm with the user before proceeding**

Do not start Task 2 until the user confirms the column swap applied and at least checks 3 + 4 (a teacher in the array sees the class; one not in it does not) pass. If a policy errors, debug it here — a half-applied migration blocks every later task.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/specs/2026-09-04-co-teachers.sql
git commit -m "docs: co-teachers migration SQL (teacher_uid -> teacher_uids)"
```

---

### Task 2: `ClassGroup.teacherIds` + `ClassController` write path + minimal caller updates

The field rename. `ClassGroup` gains `teacherIds: List<String>` and a **temporary** `teacherId` getter so the three UI files keep compiling; those move to real multi-select in Tasks 4-5, and the getter is deleted in Task 5.

**Files:**
- Modify: `lib/core/models/class_group.dart`
- Create: `test/core/models/class_group_test.dart`
- Modify: `lib/core/controllers/class_controller.dart`
- Modify: `lib/shared/widgets/class_form_dialog.dart`
- Modify: `lib/features/director/screens/class_detail_screen.dart`
- Modify: `lib/features/director/screens/manage_classes_screen.dart`
- Modify: `test/features/director/screens/class_detail_screen_test.dart`
- Modify: `test/features/director/screens/manage_classes_screen_test.dart`

**Interfaces:**
- Consumes: the migrated `classes.teacher_uids` column (Task 1).
- Produces:
  - `ClassGroup.teacherIds` (`List<String>`, `const []` when absent/null/empty), plus `String? get teacherId => teacherIds.isEmpty ? null : teacherIds.first;` marked as a temporary bridge.
  - `ClassController.createClass({required String name, required List<String> teacherIds, required String centerId, required String actorUid})` and `updateClass({required String id, required String name, required List<String> teacherIds, required String actorUid})` — write the `teacher_uids` column.
  - `ClassController.fetchForTeacher(String teacherId)` — filters with `.contains('teacher_uids', [teacherId])`.
  - `ClassFormResult` = `({String name, List<String> teacherIds})`.

- [ ] **Step 1: Write the failing model test**

Create `test/core/models/class_group_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/core/models/class_group.dart';

void main() {
  group('ClassGroup.fromJson', () {
    Map<String, dynamic> row({Object? teacherUids = const <String>[]}) => {
      'id': 'class-1',
      'name': 'Sunflowers',
      'teacher_uids': teacherUids,
      'center_id': 'center-1',
      'avatar_path': null,
      'created_at': '2026-09-04T00:00:00.000Z',
      'updated_at': '2026-09-04T00:00:00.000Z',
      'created_by': 'director-1',
      'updated_by': 'director-1',
    };

    test('parses a multi-element teacher_uids array', () {
      final c = ClassGroup.fromJson(row(teacherUids: ['t-1', 't-2']));
      expect(c.teacherIds, ['t-1', 't-2']);
    });

    test('an empty array gives an empty list', () {
      expect(ClassGroup.fromJson(row(teacherUids: <String>[])).teacherIds, isEmpty);
    });

    test('a null or missing teacher_uids gives an empty list', () {
      expect(ClassGroup.fromJson(row(teacherUids: null)).teacherIds, isEmpty);
      final noKey = row()..remove('teacher_uids');
      expect(ClassGroup.fromJson(noKey).teacherIds, isEmpty);
    });

    test('the teacherId bridge getter returns the first id, or null when empty', () {
      expect(ClassGroup.fromJson(row(teacherUids: ['t-1', 't-2'])).teacherId, 't-1');
      expect(ClassGroup.fromJson(row(teacherUids: <String>[])).teacherId, isNull);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/models/class_group_test.dart`
Expected: FAIL — `teacherIds` isn't defined on `ClassGroup`.

- [ ] **Step 3: Change the model**

In `lib/core/models/class_group.dart`:

- Replace `final String? teacherId;` with:

```dart
  final List<String> teacherIds; // teacher_uids: every teacher on this class

  // Temporary bridge for call sites not yet moved to multi-select (removed
  // in the co-teachers plan's Task 5). Prefer teacherIds.
  String? get teacherId => teacherIds.isEmpty ? null : teacherIds.first;
```

- In the constructor, replace `required this.teacherId,` with `required this.teacherIds,`.
- In `fromJson`, replace `teacherId: json['teacher_uid'] as String?,` with:

```dart
    teacherIds: (json['teacher_uids'] as List?)?.cast<String>() ?? const [],
```

- Update the class doc comment's first line to say a class has *zero or more* assigned teachers.

- [ ] **Step 4: Change `ClassController`**

In `lib/core/controllers/class_controller.dart`:

- `fetchForTeacher`:

```dart
  Future<List<ClassGroup>> fetchForTeacher(String teacherId) async {
    final rows = await _client
        .from('classes')
        .select()
        .contains('teacher_uids', [teacherId])
        .order('name');
    return (rows as List)
        .map((row) => ClassGroup.fromJson(row as Map<String, dynamic>))
        .toList();
  }
```

- `createClass` — param `required String? teacherId` → `required List<String> teacherIds`; payload key `'teacher_uid': teacherId` → `'teacher_uids': teacherIds`.
- `updateClass` — same substitution.

- [ ] **Step 5: Update the three UI callers minimally (compile + keep current single-teacher UX)**

`lib/shared/widgets/class_form_dialog.dart`:
- `typedef ClassFormResult = ({String name, List<String> teacherIds});`
- The dialog still shows its single `DropdownButtonFormField` for now. On Save, return `teacherIds: _teacherId == null ? const [] : [_teacherId!]`.

`lib/features/director/screens/class_detail_screen.dart`:
- `_save`'s `updateClass(...)` call: `teacherId: _teacherId` → `teacherIds: _teacherId == null ? const [] : [_teacherId!]`.
- `initState` / `_cancelEdit` keep reading `widget.classGroup.teacherId` (the bridge getter) — unchanged.

`lib/features/director/screens/manage_classes_screen.dart`:
- `_create`'s `createClass(...)` call: `teacherId: result.teacherId` → `teacherIds: result.teacherIds`.
- The list row still reads `classGroup.teacherId` (bridge) for now — unchanged.

- [ ] **Step 6: Fix the two screen test fixtures**

`test/features/director/screens/class_detail_screen_test.dart` — `_class()` helper: `teacherId: null` → `teacherIds: const []`. In the `saving writes ... via updateClass` test, the `when`/`verify` on `mockClasses.updateClass` change the named arg `teacherId: any(named: 'teacherId')` → `teacherIds: any(named: 'teacherIds')` and `teacherId: null` → `teacherIds: const []`. Register a fallback in `setUpAll` if mocktail needs it for the list type: `registerFallbackValue(<String>[]);`.

`test/features/director/screens/manage_classes_screen_test.dart` — `_class(...)` helper: `teacherId: teacherId` → `teacherIds: teacherId == null ? const [] : [teacherId]` (keep the helper's `String? teacherId` param so existing call sites read unchanged). Any `createClass` / `updateClass` `when`/`verify` gets the `teacherIds` arg rename + a `registerFallbackValue(<String>[])` if needed.

- [ ] **Step 7: Run analyze and the full suite**

Run: `flutter analyze`
Expected: `No issues found!` (a missed `.teacherId` write site or `teacher_uid` key shows here.)

Run: `flutter test`
Expected: `All tests passed!`. Report the real count.

- [ ] **Step 8: Commit**

```bash
git add lib/core/models/class_group.dart test/core/models/class_group_test.dart lib/core/controllers/class_controller.dart lib/shared/widgets/class_form_dialog.dart lib/features/director/screens/class_detail_screen.dart lib/features/director/screens/manage_classes_screen.dart test/features/director/screens/class_detail_screen_test.dart test/features/director/screens/manage_classes_screen_test.dart
git commit -m "feat: ClassGroup.teacherIds and array-backed class teacher writes"
```

---

### Task 3: `TeacherMultiSelect` widget

Isolated, no consumers yet. Full TDD.

**Files:**
- Create: `lib/shared/widgets/teacher_multi_select.dart`
- Test: `test/shared/widgets/teacher_multi_select_test.dart`

**Interfaces:**
- Consumes: `AppUser` (existing).
- Produces: `TeacherMultiSelect({required List<AppUser> allTeachers, required List<String> selectedIds, required ValueChanged<List<String>> onChanged})` — a `StatelessWidget`. Renders selected teachers as deletable `Chip`s and an "Add teacher" `DropdownButton` of the not-yet-selected `allTeachers`. Every mutation calls `onChanged` with the **new** id list (append on add, remove on chip delete). Purely presentational — no fetching, no internal selection state.

- [ ] **Step 1: Write the failing test**

Create `test/shared/widgets/teacher_multi_select_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/core/models/app_user.dart';
import 'package:kids_management/shared/widgets/teacher_multi_select.dart';

AppUser _t(String id, String name) => AppUser(
  id: id,
  role: 'teacher',
  name: name,
  phone: '',
  centerId: 'center-1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

void main() {
  final all = [_t('t-1', 'Aisha'), _t('t-2', 'Ben'), _t('t-3', 'Chen')];

  Future<void> pump(
    WidgetTester tester, {
    required List<String> selectedIds,
    required ValueChanged<List<String>> onChanged,
  }) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TeacherMultiSelect(
            allTeachers: all,
            selectedIds: selectedIds,
            onChanged: onChanged,
          ),
        ),
      ));

  testWidgets('renders a chip per selected teacher, in the given order',
      (tester) async {
    await pump(tester, selectedIds: ['t-2', 't-1'], onChanged: (_) {});
    expect(find.widgetWithText(Chip, 'Ben'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Aisha'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Chen'), findsNothing);
  });

  testWidgets('no chips when nothing is selected', (tester) async {
    await pump(tester, selectedIds: const [], onChanged: (_) {});
    expect(find.byType(Chip), findsNothing);
  });

  testWidgets('the add dropdown offers only not-yet-selected teachers',
      (tester) async {
    await pump(tester, selectedIds: ['t-1'], onChanged: (_) {});
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    // Aisha (t-1) is already selected -> not offered. Ben and Chen are.
    expect(find.text('Ben').hitTestable(), findsOneWidget);
    expect(find.text('Chen').hitTestable(), findsOneWidget);
  });

  testWidgets('picking a teacher from the dropdown appends its id', (tester) async {
    List<String>? out;
    await pump(tester, selectedIds: ['t-1'], onChanged: (v) => out = v);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ben').last);
    await tester.pumpAndSettle();
    expect(out, ['t-1', 't-2']);
  });

  testWidgets('deleting a chip removes that id', (tester) async {
    List<String>? out;
    await pump(tester, selectedIds: ['t-1', 't-2'], onChanged: (v) => out = v);
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(Chip, 'Aisha'),
        matching: find.byIcon(Icons.cancel),
      ),
    );
    await tester.pumpAndSettle();
    expect(out, ['t-2']);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/shared/widgets/teacher_multi_select_test.dart`
Expected: FAIL — cannot resolve `teacher_multi_select.dart`.

- [ ] **Step 3: Write the widget**

Create `lib/shared/widgets/teacher_multi_select.dart`:

```dart
import 'package:flutter/material.dart';
import '../../core/models/app_user.dart';

// A form control for assigning teachers to a class: the current selection as
// deletable chips, plus an "Add teacher" dropdown of the teachers not yet
// picked. Stateless -- it renders `selectedIds` and reports every change back
// through `onChanged` with the full new list; the parent owns the state.
class TeacherMultiSelect extends StatelessWidget {
  const TeacherMultiSelect({
    super.key,
    required this.allTeachers,
    required this.selectedIds,
    required this.onChanged,
  });

  final List<AppUser> allTeachers;
  final List<String> selectedIds;
  final ValueChanged<List<String>> onChanged;

  String _nameFor(String id) => allTeachers
      .firstWhere(
        (t) => t.id == id,
        orElse: () => AppUser(
          id: id,
          role: 'teacher',
          name: 'Unknown teacher',
          phone: '',
          centerId: '',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          createdBy: null,
          updatedBy: null,
        ),
      )
      .name;

  @override
  Widget build(BuildContext context) {
    final unselected =
        allTeachers.where((t) => !selectedIds.contains(t.id)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selectedIds.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final id in selectedIds)
                Chip(
                  label: Text(_nameFor(id)),
                  onDeleted: () =>
                      onChanged([...selectedIds]..remove(id)),
                ),
            ],
          ),
        const SizedBox(height: 8),
        DropdownButton<String>(
          isExpanded: true,
          hint: const Text('Add teacher'),
          value: null,
          items: [
            for (final t in unselected)
              DropdownMenuItem(value: t.id, child: Text(t.name)),
          ],
          onChanged: unselected.isEmpty
              ? null
              : (id) {
                  if (id != null) onChanged([...selectedIds, id]);
                },
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/shared/widgets/teacher_multi_select_test.dart`
Expected: PASS — 5 tests.

- [ ] **Step 5: Run analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/shared/widgets/teacher_multi_select.dart test/shared/widgets/teacher_multi_select_test.dart
git commit -m "feat: TeacherMultiSelect widget"
```

---

### Task 4: Wire `TeacherMultiSelect` into the create dialog and the class detail screen

**Files:**
- Modify: `lib/shared/widgets/class_form_dialog.dart`
- Modify: `lib/features/director/screens/class_detail_screen.dart`
- Modify: `test/features/director/screens/class_detail_screen_test.dart`
- Test: `test/shared/widgets/class_form_dialog_test.dart` (new — the dialog has no test today)

**Interfaces:**
- Consumes: `TeacherMultiSelect` (Task 3), `ClassFormResult` with `teacherIds` (Task 2).
- Produces: no signature changes — both surfaces just swap their single `DropdownButtonFormField` for a `TeacherMultiSelect` holding a local `List<String>`.

- [ ] **Step 1: Update `class_form_dialog.dart`**

- `_ClassFormDialogState`: replace `late String? _teacherId;` with `late List<String> _teacherIds;`. In `initState`, seed it by filtering `widget.initialTeacherIds` (rename the widget/function param from `String? initialTeacherId` to `List<String> initialTeacherIds = const []`) to ids present in `widget.teachers`.
- Replace the `DropdownButtonFormField` with:

```dart
            TeacherMultiSelect(
              allTeachers: widget.teachers,
              selectedIds: _teacherIds,
              onChanged: (ids) => setState(() => _teacherIds = ids),
            ),
```

- On Save: `Navigator.of(context).pop((name: _nameController.text.trim(), teacherIds: _teacherIds));`
- Update `showClassFormDialog`'s param the same way (`initialTeacherIds`). Update its one caller in `manage_classes_screen._create` — it currently passes no initial teacher, so just drop the arg or pass `const []`.

- [ ] **Step 2: Update `class_detail_screen.dart`**

- Replace `late String? _teacherId;` with `late List<String> _teacherIds;`.
- `initState`: `_teacherIds = [...widget.classGroup.teacherIds];`
- `_cancelEdit`: `_teacherIds = [...widget.classGroup.teacherIds];`
- `_save`: `teacherIds: _teacherIds`.
- In the `FutureBuilder`, view mode: show the joined names — `widget.classGroup.teacherIds.map((id) => nameFor(id)).join(', ')` or `'Unassigned'` when empty (resolve names from the loaded `teachers` list; keep the existing "…" while loading). Edit mode: replace the `DropdownButtonFormField` with `TeacherMultiSelect(allTeachers: teachers, selectedIds: _teacherIds, onChanged: (ids) => setState(() => _teacherIds = ids))`.

- [ ] **Step 3: Update `class_detail_screen_test.dart`**

The `saving writes the edited name and teacher via updateClass` test: after entering edit mode, drive the new `TeacherMultiSelect` (open its `DropdownButton<String>`, pick `Ms. Rose`) and assert `updateClass` is called with `teacherIds: ['teacher-1']`. Keep a variant that saves with no teacher selected → `teacherIds: const []`. Adjust the `when`/`verify` arg names to `teacherIds`.

- [ ] **Step 4: Write `class_form_dialog_test.dart`**

Create `test/shared/widgets/class_form_dialog_test.dart` — pump a host that opens `showClassFormDialog` with `teachers: [Aisha, Ben]`, then:
- entering a name and picking two teachers and tapping Save resolves the future with `(name: 'Toddlers', teacherIds: ['t-1', 't-2'])` (order = pick order);
- Save with no teacher resolves `teacherIds: const []`;
- Cancel resolves `null`;
- empty name shows the validator error and does not pop.

- [ ] **Step 5: Run the touched tests, then analyze + full suite**

Run: `flutter test test/shared/widgets/class_form_dialog_test.dart test/shared/widgets/teacher_multi_select_test.dart test/features/director/screens/class_detail_screen_test.dart`
Expected: PASS.

Run: `flutter analyze && flutter test`
Expected: `No issues found!` and `All tests passed!`. Report the count.

- [ ] **Step 6: Commit**

```bash
git add lib/shared/widgets/class_form_dialog.dart lib/features/director/screens/class_detail_screen.dart test/features/director/screens/class_detail_screen_test.dart test/shared/widgets/class_form_dialog_test.dart
git commit -m "feat: assign multiple teachers to a class from the create dialog and detail screen"
```

---

### Task 5: `manage_classes_screen` multi-name display; delete the `teacherId` bridge

**Files:**
- Modify: `lib/features/director/screens/manage_classes_screen.dart`
- Modify: `lib/core/models/class_group.dart`
- Modify: `test/features/director/screens/manage_classes_screen_test.dart`
- Modify: `test/core/models/class_group_test.dart`

**Interfaces:**
- Consumes: `ClassGroup.teacherIds`.
- Produces: `ClassGroup` no longer has the `teacherId` getter. The class list row shows all assigned teacher names.

- [ ] **Step 1: Multi-name display**

In `manage_classes_screen.dart`'s `itemBuilder`, replace the single-name lookup with:

```dart
              final names = classGroup.teacherIds
                  .map((id) => data.teachersById[id] ?? 'Unknown teacher')
                  .toList();
              final teacherLine = names.isEmpty
                  ? 'No teacher assigned'
                  : names.length <= 2
                      ? names.join(', ')
                      : '${names.take(2).join(', ')} +${names.length - 2}';
```

and use `teacherLine` in the `subtitle`.

- [ ] **Step 2: Delete the bridge getter**

In `lib/core/models/class_group.dart`, remove the `String? get teacherId => ...` getter and its comment. Run `flutter analyze` — it must still be clean (Tasks 2 and 4 removed every read of `.teacherId`; if analyze flags one, that call site was missed and must move to `teacherIds`).

- [ ] **Step 3: Update tests**

`test/core/models/class_group_test.dart` — delete the `teacherId bridge getter` test.

`test/features/director/screens/manage_classes_screen_test.dart` — add: a class with `teacherIds: ['t-1', 't-2']` and a `teachersById` covering both shows `"Rose, Ben"` (or whatever the fixtures name them); a class with `const []` shows `"No teacher assigned"`; a class with three teachers shows `"A, B +1"`. Keep the `_class` helper but change its param to `List<String> teacherIds = const []`.

- [ ] **Step 4: Analyze + full suite**

Run: `flutter analyze && flutter test`
Expected: clean, all pass. Report the count.

- [ ] **Step 5: Commit**

```bash
git add lib/features/director/screens/manage_classes_screen.dart lib/core/models/class_group.dart test/features/director/screens/manage_classes_screen_test.dart test/core/models/class_group_test.dart
git commit -m "feat: class list shows all assigned teachers; drop the teacherId bridge"
```

---

### Task 6: `TeacherController.fetchCoTeachers`

**Files:**
- Modify: `lib/core/controllers/teacher_controller.dart`

**Interfaces:**
- Consumes: the migrated `classes.teacher_uids` and the widened `profiles_select` (Task 1).
- Produces: `Future<List<AppUser>> fetchCoTeachers(String myUid)` — teachers sharing at least one class with `myUid`, excluding `myUid`, ordered by name; `[]` when there are none. Piece C consumes this.

- [ ] **Step 1: Add the method**

In `lib/core/controllers/teacher_controller.dart`:

```dart
  // Teachers who share at least one class with `myUid` (co-teachers),
  // excluding the caller. Two queries, like ChildController.fetchParentsForChild:
  // first the caller's classes (RLS already limits `classes` to ones they are
  // on), then the profiles for the union of those classes' teacher_uids.
  // Relies on the co-teacher branch of profiles_select for the second query.
  Future<List<AppUser>> fetchCoTeachers(String myUid) async {
    final classRows = await _client
        .from('classes')
        .select('teacher_uids')
        .contains('teacher_uids', [myUid]);
    final ids = <String>{
      for (final row in classRows as List)
        ...((row['teacher_uids'] as List).cast<String>()),
    }..remove(myUid);
    if (ids.isEmpty) return [];
    final rows = await _client
        .from('profiles')
        .select()
        .inFilter('id', ids.toList())
        .order('name');
    return (rows as List)
        .map((row) => AppUser.fromJson(row as Map<String, dynamic>))
        .toList();
  }
```

- [ ] **Step 2: Analyze + full suite**

Run: `flutter analyze && flutter test`
Expected: `No issues found!`, all pass (no test references `fetchCoTeachers` yet). Report the count.

- [ ] **Step 3: Commit**

```bash
git add lib/core/controllers/teacher_controller.dart
git commit -m "feat: TeacherController.fetchCoTeachers"
```

---

### Task 7: Update the design docs

**Files:**
- Modify: `docs/superpowers/specs/2026-09-04-co-teachers-design.md`
- Modify: `docs/superpowers/specs/2026-07-01-childcare-management-design.md`
- Modify: `docs/superpowers/specs/2026-08-07-security-hardening.sql`

- [ ] **Step 1: Flip the spec status**

`2026-09-04-co-teachers-design.md`: `**Status:** approved, not yet implemented` → `**Status:** implemented 2026-09-04`.

- [ ] **Step 2: Update the main design spec**

`2026-07-01-childcare-management-design.md`:
- The `classes` schema block: `teacher_uid UUID REFERENCES auth.users(id)` → `teacher_uids UUID[] NOT NULL DEFAULT '{}'` with a one-line note that a class has any number of teachers, all equal, and a pointer to `2026-09-04-co-teachers-design.md`.
- The "Future — multiple teachers per class" note: mark it **done** (2026-09-04), note the array-column choice over the originally-floated `class_teachers` junction, and that `children.teacher_id` deliberately still stands separate.
- Any prose that says "the class's teacher" (singular) near schedule/lesson-plan RLS: adjust to "a teacher on the class".

- [ ] **Step 3: Note the rewrite in the hardening SQL doc**

`2026-08-07-security-hardening.sql`: add a header comment near the `classes` / `schedule_entries` / `lesson_plans` / storage sections stating that the `teacher_uid = auth.uid()` tests were superseded on 2026-09-04 by `auth.uid() = ANY(teacher_uids)` (see `2026-09-04-co-teachers.sql`), so this file no longer reflects the live policies for those spots. Do not rewrite the SQL bodies here — that file is a historical record of the M-series pass; the live definitions are in the co-teachers migration.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-09-04-co-teachers-design.md docs/superpowers/specs/2026-07-01-childcare-management-design.md docs/superpowers/specs/2026-08-07-security-hardening.sql
git commit -m "docs: record co-teachers as implemented"
```

---

## Done when

- The user has run `2026-09-04-co-teachers.sql` and confirmed a teacher in `teacher_uids` sees their class while one not in it does not, and a co-teacher can read the other's profile.
- `flutter analyze` is clean and the full suite passes (report the real count).
- A director can assign several teachers to a class from both the create dialog and the class detail screen; the class list shows all of them.
- `classes.teacher_uid` no longer exists; nothing in the app or the six rewritten policies references it.
- `children.teacher_id` and every behaviour keyed off it are byte-for-byte unchanged.
- `TeacherController.fetchCoTeachers` returns co-teachers for a teacher, ready for Piece C.
