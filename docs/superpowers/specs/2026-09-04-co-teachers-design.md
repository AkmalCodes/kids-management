# Co-teachers on a class — design

**Date:** 2026-09-04
**Status:** implemented 2026-09-04

## Problem

`classes` records exactly one teacher, in the `teacher_uid` column. Real
centres put more than one teacher on a room. This is piece **B** of a
three-part change (A: grid tile label — shipped; B: this; C: a two-grid
teacher attendance page that lists a teacher's co-teachers). C depends on B.

The main design spec has anticipated this since the class-schedule work
(`docs/superpowers/specs/2026-07-01-childcare-management-design.md`, the
"Future — multiple teachers per class" note): schedules were deliberately made
**class-owned** (`schedule_entries.type = 'class'`, `ref_id = class_id`) rather
than teacher-owned so that "whose schedule does the parent see" has one answer
regardless of teacher count.

## Goals

- A class can have zero, one, or many teachers.
- Every teacher on a class has the **same** rights the single `teacher_uid`
  teacher has today: see the class, see/add its schedule entries, see its
  approved lesson plans, load its photo.
- A teacher can view the **profile** (read-only) of any teacher who shares a
  class with them. They cannot see a co-teacher's clock-in/out or mark it —
  `staff_attendance` RLS is untouched.
- A director assigns/removes teachers on a class, at creation and afterward.

## Non-goals

- The two-grid teacher attendance page (piece C).
- Any change to `children.teacher_id`. That is a separate, direct column that
  drives which children a teacher sees for attendance and daily reports. A
  child still has exactly one assigned teacher; co-teaching a *class* does not
  change who sees that child's attendance. Consolidating `children.teacher_id`
  with class membership is explicitly out of scope.
- A "lead" / "primary" teacher concept. All teachers on a class are equal.
  `teacher_uid` is removed, not demoted.
- `schedule_entries` update/delete rules. Those are already `created_by`-based
  (a teacher edits only entries they created); that is unchanged, so a
  co-teacher gets exactly what the current single teacher gets — can create
  class entries, can edit/delete only their own.
- Automatic assignment of a teacher to a class when a child is assigned to
  that teacher. Class membership is set by the director explicitly.

## Schema

One array column on `classes`, replacing `teacher_uid`:

```sql
-- 1. add
ALTER TABLE classes ADD COLUMN teacher_uids UUID[] NOT NULL DEFAULT '{}';

-- 2. backfill from the single column
UPDATE classes SET teacher_uids = ARRAY[teacher_uid] WHERE teacher_uid IS NOT NULL;

-- 3. ... rewrite every reference (see "RLS / functions / storage") ...

-- 4. drop the old column LAST, once nothing references it
ALTER TABLE classes DROP COLUMN teacher_uid;
```

`UUID[]` — a Postgres array column: one `classes` row holds all its teachers'
ids in that one cell. Chosen over a `class_teachers` junction table on the
user's call: no new table, no new model/controller, and array-membership RLS
(`auth.uid() = ANY(teacher_uids)`) is a one-liner that scales to any teacher
count. `NOT NULL DEFAULT '{}'` so the column is always a real (possibly empty)
array, never null — callers never branch on null.

### Deleted-teacher cleanup

A Postgres array has no per-element foreign key, so deleting a teacher's
account does not remove their id from `teacher_uids`. A trigger handles it:

```sql
CREATE OR REPLACE FUNCTION remove_teacher_from_classes()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  UPDATE public.classes
     SET teacher_uids = array_remove(teacher_uids, OLD.id)
   WHERE OLD.id = ANY(teacher_uids);
  RETURN OLD;
END;
$$;

CREATE TRIGGER profiles_after_delete_clear_class_teacher
  AFTER DELETE ON profiles
  FOR EACH ROW EXECUTE FUNCTION remove_teacher_from_classes();
```

On `profiles` (one row per user, deleted as part of the app's user-removal
path) rather than `auth.users`. A stale id left in an array is harmless
anyway — it just matches no `auth.uid()` and grants nothing — so this is
tidiness, not a security control.

## RLS / functions / storage

Every reference to `classes.teacher_uid = auth.uid()` becomes
`auth.uid() = ANY(classes.teacher_uids)` (adjusting the table alias where the
policy uses one). Exhaustive list — all six, in the M-series hardening SQL
(`docs/superpowers/specs/2026-08-07-security-hardening.sql`), plus the two the
spec keeps in sync:

| Policy / function | File:line (hardening SQL) | Branch |
|---|---|---|
| `schedule_entries_select` | ~99 | `type = 'class'` teacher branch |
| `schedule_entries_insert` | ~109 | `type = 'class'` teacher branch |
| `lesson_plans_select` | ~152 | approved + teacher branch |
| `classes_select` | ~185 | `OR teacher_uid = auth.uid()` |
| `class_plan_subjects(p_class_id)` SECURITY DEFINER fn | ~270 | teacher branch |
| `class_avatars_select` storage policy | ~350 | teacher branch |

`class_avatars_update` is director-only (`center_id = my_center()`) — not
touched. `schedule_entries_update` / `_delete` are `created_by`-based — not
touched (see non-goals).

### New: teacher reads a co-teacher's profile

`profiles_select` today is `id = auth.uid() OR (director AND center_id =
my_center())` (from the hardening SQL). Add one branch via a helper:

```sql
CREATE OR REPLACE FUNCTION shares_class_with(target UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.classes c
    WHERE auth.uid() = ANY(c.teacher_uids)
      AND target = ANY(c.teacher_uids)
  );
$$;
```

New `profiles_select`:

```sql
CREATE POLICY "profiles_select" ON profiles FOR SELECT USING (
  id = auth.uid()
  OR (current_role_name() = 'director' AND center_id = my_center())
  OR shares_class_with(id)
);
```

`SECURITY DEFINER` so the `classes` lookup inside it is not itself
re-filtered by `classes` RLS (avoids a confusing dependency between the two
tables' policies) and stays fast. `STABLE`, `search_path = ''`, and
schema-qualified names — matching every other helper in the hardening SQL.

### Verification (manual, by the user)

This project has no automated RLS test suite (verified — no pgTAP, no
policy-test file). The migration ships as one ordered `.sql` file plus a
step-by-step walkthrough the user runs in the Supabase SQL editor,
impersonating a teacher via `set_config('request.jwt.claims', …)` — the same
method used for `docs/superpowers/specs/2026-09-02-staff-attendance-schema.md`
Task 1. The walkthrough must confirm, at minimum:

- a teacher in `teacher_uids` can `SELECT` the class, its `type='class'`
  schedule entries, and its approved lesson plans;
- a teacher **not** in `teacher_uids` cannot;
- adding a second teacher's id to the array grants that teacher the same
  access, with no SQL change;
- the second teacher can now `SELECT` the first teacher's `profiles` row, and
  a teacher sharing no class with them still cannot;
- removing an id from the array revokes access;
- deleting a teacher's `profiles` row removes their id from every
  `teacher_uids` array;
- the old `teacher_uid` column is gone and nothing errors.

## Model + controller

### `ClassGroup` (`lib/core/models/class_group.dart`)

- `final String? teacherId;` → `final List<String> teacherIds;`
- `fromJson`: `teacherIds: (json['teacher_uids'] as List?)?.cast<String>() ?? const []`
- The constructor param becomes `required this.teacherIds` (callers always
  have a list, even if empty).

### `ClassController` (`lib/core/controllers/class_controller.dart`)

- `fetchForTeacher(String teacherId)` — filter changes from
  `.eq('teacher_uid', teacherId)` to `.contains('teacher_uids', [teacherId])`
  (Postgrest "array contains").
- `createClass` / `updateClass` — the `String? teacherId` param becomes
  `List<String> teacherIds`, written to the `teacher_uids` column.
- No dedicated `class_controller_test.dart` — repo convention for
  Supabase-backed controllers (verified: no `attendance_controller_test.dart`
  etc.); proven through the widget tests of the screens that use it.

### `ClassFormResult` (`lib/shared/widgets/class_form_dialog.dart`)

`typedef ClassFormResult = ({String name, String? teacherId});` →
`({String name, List<String> teacherIds});`

### New: `fetchCoTeachers`

`TeacherController.fetchCoTeachers(String myUid)` →
`Future<List<AppUser>>`. Two queries, mirroring
`ChildController.fetchParentsForChild`'s pattern:

1. `classes` where `teacher_uids` contains `myUid` → collect the union of all
   their `teacher_uids`, minus `myUid`, deduplicated.
2. If non-empty, `profiles` `.inFilter('id', thoseIds)` → `AppUser` list,
   ordered by name.

Returns `[]` when the teacher shares no class with anyone. Relies on the
widened `profiles_select` for step 2. Piece C consumes this; it is added here
so B is independently complete and testable.

## Director UI

### New shared widget: `TeacherMultiSelect`

`lib/shared/widgets/teacher_multi_select.dart` — a form control:

- Renders the currently-selected teachers as `Chip`s with a delete `x`.
- An "Add teacher" `DropdownButton` (or a button opening a menu) listing the
  centre's teachers **not** already selected; picking one appends it.
- Props: `List<AppUser> allTeachers`, `List<String> selectedIds`,
  `ValueChanged<List<String>> onChanged`. Purely presentational — no fetching.
- Empty state: just the "Add teacher" control, no chips.

Used by **both**:

- **`class_form_dialog.dart`** (create) — replaces the single
  `DropdownButtonFormField`. Dialog returns `teacherIds: <list>` (possibly
  empty).
- **`class_detail_screen.dart`** (director edit) — replaces its own single
  teacher `DropdownButtonFormField` (this screen has its own, separate from
  the dialog). Save writes the list via `updateClass`.

### `manage_classes_screen.dart`

The per-class list row currently shows one teacher name (or "Unassigned").
It shows the joined names — `teachers.map((t) => t.name).join(', ')` — or
`"<first> +N"` when the list is long, `"Unassigned"` when empty. Uses the
already-loaded `teachersById` map.

## Consumers checked (no change needed)

- `child_detail_screen.dart`, `enroll_child_screen.dart` — set
  `children.teacher_id`, a different column. Untouched.
- `daily_report` / `lesson_plan` models carry their own `teacher_id`
  (the authoring teacher), unrelated to class membership. Untouched.
- Parent class-schedule view — `schedule_entries` for `type='class'` are
  fetched by `class_id`; the parent branch of `schedule_entries_select`
  already keys off `children_parents`, not the teacher. Any code path that
  read `ClassGroup.teacherId` purely to look up "the class's teacher" is
  adjusted to not need it, or to take `teacherIds.first` where a single
  display name is genuinely wanted (flagged in the plan per call site).

## Testing

- **`test/core/models/class_group_test.dart`** — `fromJson` parses
  `teacher_uids` into a `List<String>`; missing / null / empty array all give
  `const []`; a multi-element array round-trips.
- **`TeacherMultiSelect`** — full widget TDD: renders chips for selected ids;
  the add-dropdown lists only unselected centre teachers; picking one fires
  `onChanged` with the id appended; tapping a chip's `x` fires `onChanged`
  with it removed; empty `selectedIds` shows no chips.
- **`class_form_dialog` test** — updated: the dialog now contains a
  `TeacherMultiSelect`, and Save returns `teacherIds` (a list). Cover
  create-with-none and create-with-two.
- **`class_detail_screen` test** — updated: the teacher editor is now
  multi-select; saving writes the full list through a mocked `updateClass`.
- **`manage_classes_screen` test** — updated: a class with two teachers shows
  both names; an empty one shows "Unassigned".
- **`ClassController`** — no new test file (convention); `flutter analyze` is
  its gate, plus the screen tests above exercise its interface through mocks.
- **`fetchCoTeachers`** — exercised through Piece C's tests when that lands;
  for B, a `TeacherController` has no existing test file and none is added
  (same convention), so its correctness rides on `flutter analyze` and a note
  in the migration walkthrough to sanity-check it against real data.
- Full Flutter suite stays green; report the real count.

## Migration ordering (the one real trap)

The single `.sql` file MUST run in this order, and the app code that reads
`teacher_uids` must land together with it (nothing may read the dropped
`teacher_uid` after the migration):

1. `ADD COLUMN teacher_uids …`
2. backfill `UPDATE`
3. create `shares_class_with`, `remove_teacher_from_classes` + trigger
4. `CREATE OR REPLACE` all six rewritten policies/function + the new
   `profiles_select`
5. `DROP COLUMN teacher_uid` — last

Dropping the column before step 4 makes every one of those policies error
("column teacher_uid does not exist") and breaks the app for every role.

## Open questions

None.
