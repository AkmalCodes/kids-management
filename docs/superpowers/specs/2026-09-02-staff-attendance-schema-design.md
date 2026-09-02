# Staff attendance schema — design

**Date:** 2026-09-02
**Status:** approved, not yet implemented

## Problem

The director wants a "People" dashboard: one place to cycle between
Teachers / Children / Classes, see attendance status at a glance, and mark
it — the same grid pattern already built for the teacher's Attendance tab
(see `docs/superpowers/specs/2026-09-01-teacher-attendance-grid-design.md`),
applied to the director's People screen.

That screen work is blocked on two facts, both discovered while scoping it:

1. **There is no way to record a teacher's own attendance.** The
   `attendance` table is children-only: `child_id UUID NOT NULL`,
   `UNIQUE (child_id, date)`. A teacher tile in the director's grid would
   have no data to show a badge from.
2. **Directors cannot mark *child* attendance either**, today. The existing
   RLS —

   ```sql
   CREATE POLICY "attendance_insert" ON attendance FOR INSERT
     WITH CHECK (
       current_role_name() = 'teacher'
       AND EXISTS (SELECT 1 FROM children WHERE children.id = attendance.child_id AND children.teacher_id = auth.uid())
     );
   ```

   — only ever matches `role = 'teacher'`. A director calling the same
   insert is rejected. The user confirmed directors should be able to mark
   students' attendance too, which this RLS does not currently allow.

This spec covers only the schema and RLS layer needed to unblock both. The
grid screen itself — the director's People/Attendance merge — is a separate
spec once this lands.

## Goals

- A teacher can mark their own attendance; a director can mark any teacher's,
  scoped to their own center.
- A director can mark any child's attendance in their own center (currently
  impossible).
- Nothing here regresses the existing teacher-marks-their-own-class-children
  path.

## Non-goals

- **The director's grid/merge screen.** Depends on this spec; specced
  separately once this is built and testable.
- **Photos on staff attendance.** Child attendance photos exist for
  handoff/safety verification with a parent — that reasoning does not apply
  to staff. Status and notes only.
- **Tracking the director's own attendance.** Scoped to teachers. A center
  typically has one director and nobody above them to mark it, so there is
  no clear "who marks the director" answer, and nothing has asked for it.
- **Reusing the `attendance` table for staff rows.** A nullable
  `child_id`/`staff_id` with a check-one-of would muddy a table whose
  current RLS and application code both assume every row is a child. A new
  table keeps both simple.

## Schema

```sql
CREATE TABLE staff_attendance (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  staff_id    UUID REFERENCES profiles(id) NOT NULL,
  center_id   UUID REFERENCES centers(id) NOT NULL,
  date        DATE NOT NULL,
  status      TEXT NOT NULL CHECK (status IN ('present', 'absent', 'late', 'excused')),
  notes       TEXT DEFAULT '',
  created_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  created_by  UUID REFERENCES auth.users(id),
  updated_by  UUID REFERENCES auth.users(id),
  UNIQUE (staff_id, date)
);
```

Field-for-field the same shape as `attendance` (`date`/`status`/`notes`/audit
columns/`UNIQUE (x, date)`), with `child_id` replaced by `staff_id` and no
photo columns. `status` keeps all four values for schema consistency with
`attendance`, even though — same as the child side — the UI this spec's
controller serves will likely only ever write `present`/`absent` at first.

`staff_id` is not constrained to `role = 'teacher'` by a table CHECK,
because role is mutable data in `profiles` and a CHECK can't reference
another table. That constraint lives in the INSERT policy instead (below),
the same place the equivalent child-side rule already lives (`attendance_insert`
checks `children.teacher_id = auth.uid()`, not a table constraint).

## RLS

```sql
-- A teacher reads their own rows; a director reads every teacher's, scoped
-- to their own center (never cross-center, matching every other director
-- policy in this project since the M1 hardening pass).
CREATE POLICY "staff_attendance_select" ON staff_attendance FOR SELECT
  USING (
    staff_id = auth.uid()
    OR (current_role_name() = 'director' AND center_id = my_center())
  );

-- A teacher may only insert their own row. A director may insert for any
-- profile that is actually a teacher in their center -- this is what stops
-- a director from creating a staff_attendance row for a parent or another
-- director by passing an arbitrary staff_id.
CREATE POLICY "staff_attendance_insert" ON staff_attendance FOR INSERT
  WITH CHECK (
    (staff_id = auth.uid() AND current_role_name() = 'teacher')
    OR (
      current_role_name() = 'director'
      AND center_id = my_center()
      AND EXISTS (SELECT 1 FROM profiles WHERE profiles.id = staff_id AND profiles.role = 'teacher')
    )
  );

CREATE POLICY "staff_attendance_update" ON staff_attendance FOR UPDATE
  USING (
    staff_id = auth.uid()
    OR (current_role_name() = 'director' AND center_id = my_center())
  );
```

`my_center()` is the existing SECURITY DEFINER helper from the M1
multi-center hardening pass — reused, not reinvented.

## Widening child attendance for directors

```sql
DROP POLICY "attendance_insert" ON attendance;
CREATE POLICY "attendance_insert" ON attendance FOR INSERT
  WITH CHECK (
    (current_role_name() = 'teacher' AND EXISTS (SELECT 1 FROM children WHERE children.id = attendance.child_id AND children.teacher_id = auth.uid()))
    OR (current_role_name() = 'director' AND child_center(attendance.child_id) = my_center())
  );

DROP POLICY "attendance_update" ON attendance;
CREATE POLICY "attendance_update" ON attendance FOR UPDATE
  USING (
    (current_role_name() = 'teacher' AND created_by = auth.uid())
    OR (current_role_name() = 'director' AND child_center(attendance.child_id) = my_center())
  );
```

`child_center(child_id)` is the existing SECURITY DEFINER helper added to
dodge RLS recursion on `children_parents` (documented in the main design
spec's M1 bug-fix note) — the same helper the `attendance_select` policy
already uses, applied here to the two policies that were missed when
`attendance_select` was widened.

`SELECT` on `attendance` is untouched: it already includes
`current_role_name() = 'director'` with no center scoping. That is a
pre-existing gap (a director can read another center's attendance rows via
this table today) but is out of scope here — this spec only widens what
directors can *write*, matching exactly what was asked. Worth a note in the
main design spec's security-findings section so it isn't lost.

## App layer

New files, mirroring the existing `Attendance`/`AttendanceController` pair:

- `lib/core/models/staff_attendance.dart` — `StaffAttendance` model,
  `AttendanceStatus` reused from `lib/core/models/attendance.dart` rather
  than duplicated (it's a shared enum, not a child-specific one).
- `lib/core/controllers/staff_attendance_controller.dart` —
  `StaffAttendanceController` with `fetchForStaff(staffId)`,
  `fetchForDate(date)`, `markAttendance({staffId, centerId, date, status,
  actorUid, existingId, notes})` — same method shapes as
  `AttendanceController`, no photo methods.

`AttendanceController.markAttendance` also gets a `notes` parameter that
callers can now meaningfully set for the director path (see the sibling
teacher-grid spec's notes discussion) — already true of the existing method
signature, not a new change here.

## The testable surface for this task

A schema change has nothing to click. Rather than ship it with no way to
verify it on a device, this task adds one small, real control — not
throwaway, not superseded by the next task — to `ProfileScreen`: a **"Mark my
attendance" present/absent toggle**, visible only when `role == 'teacher'`,
calling `StaffAttendanceController.markAttendance` with `staffId:
currentUser.id`. This exercises exactly the self-marking RLS path end to end.

The director-facing surface (marking any teacher, seeing every teacher's
status) is not built here — it is the reason the next spec (the People/
Attendance merge) exists. Building a throwaway director screen in this task
only to delete it next would be wasted work.

## Testing

**SQL / RLS.** There is no automated RLS test suite in this project (checked:
no pgTAP, no policy-test file anywhere in the repo) — `2026-08-07-security-
hardening.sql` is hand-written policy SQL with no test companion. RLS has
been verified manually so far, and this spec follows that existing practice
rather than introducing a new one: after migrating, verify each case below
by hand (Supabase SQL editor, `SET request.jwt.claims` to impersonate each
role, or equivalent) rather than by running a suite. Introducing an automated
RLS test framework is real, valuable work, but it is infrastructure for the
whole project, not something to bootstrap inside this one feature.

- a teacher can insert/select/update their own `staff_attendance` row
- a teacher cannot insert a row for a different `staff_id`
- a director can insert/update a teacher's row in their own center
- a director cannot insert a row for a `staff_id` in a different center
- a director cannot insert a row where `staff_id` belongs to a parent or
  another director (the `profiles.role = 'teacher'` check)
- a director can now insert/update `attendance` (child) rows in their own
  center; still cannot in a different center
- the existing teacher-marks-own-class-children path on `attendance` is
  unchanged (regression check)

**Dart**, mocktail against `StaffAttendanceController`, mirroring
`test/core/controllers/attendance_controller_test.dart`'s existing shape.

**Widget**, for the new `ProfileScreen` control:
- the toggle is visible for a teacher, absent for a parent or director
- tapping Present calls `markAttendance` with the signed-in user's own id
- the full Flutter suite (226 tests going into this task) stays green

## Open questions

None. Every design choice above traces to an explicit answer in this
conversation or an existing convention in the codebase (`my_center()`,
`child_center()`, the `attendance` table's own shape).
