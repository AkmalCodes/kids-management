# Staff clock-in/out — design

**Date:** 2026-09-02
**Status:** approved, not yet implemented

## Problem

The previous piece of work (`docs/superpowers/specs/2026-09-02-staff-attendance-schema-design.md`)
shipped a Present/Absent chip toggle on the teacher's Profile tab. Replacing
it: instead of choosing a status, a teacher taps **Clock in** at the start of
their day and **Clock out** at the end, each with a confirmation step. The
recorded times will feed HR and, later, payroll — so precision and an audit
trail matter more here than they did for a same-day status toggle.

## Goals

- A teacher records the real time they started and finished work, not a
  same-day status choice.
- Both actions require an explicit confirm step before writing — this is
  payroll-adjacent data; an accidental tap must not silently record a time.
- The record for a day, once both times are set, cannot be silently
  overwritten.
- Nothing about who-can-mark-whom changes: RLS from the previous spec is
  untouched.

## Non-goals

- **Automatic clock-out.** Considered and declined — it would need a
  per-center "working hours" concept (does not exist) and a server-side
  scheduled job (this project has none). The teacher taps Clock out
  themselves; "naturally happens at the end of the day" describes when they
  do it, not the system doing it for them.
- **A director marking a teacher's attendance.** Still deferred to the
  People/Attendance merge, as in the previous spec. This task's schema does
  not block it: a director inserting `status: 'absent'` with both clock
  columns `null` remains valid.
- **Payroll integration itself.** Only mentioned as the reason precision and
  a data-integrity constraint matter now. No payroll code exists or is
  planned here.
- **Editing a past day's clock times.** Once a day is locked (both times
  set), there is no UI to change it in this task. A correction path (if one
  is ever needed) is a director-facing concern for a later task.

## Schema

```sql
ALTER TABLE staff_attendance
  ADD COLUMN clock_in_at TIMESTAMPTZ,
  ADD COLUMN clock_out_at TIMESTAMPTZ,
  ADD CONSTRAINT staff_attendance_clock_order
    CHECK (clock_out_at IS NULL OR (clock_in_at IS NOT NULL AND clock_out_at > clock_in_at));
```

Additive only — extends the table from the previous spec, does not replace
it. `status`, RLS, and everything else about that table are unchanged.

The CHECK constraint is the one piece of genuinely new rigor this task adds
over the previous spec: it makes "clocked out before/without clocking in" a
database-level impossibility, not just an app-level convention. Worth having
specifically because this data is headed toward payroll — a corrupt record
there is a pay dispute, not a cosmetic bug.

`clock_in_at`/`clock_out_at` are distinct from the existing `created_at`/
`updated_at` audit columns. Reusing the audit timestamps as the clock times
was considered and rejected: it would conflate "when this row was last
touched" (which could be a future correction, an unrelated field edit) with
"when the person actually clocked in/out" — two different facts that need to
stay independently readable.

## Controller

Two new, explicitly named methods on `StaffAttendanceController` — not one
method with nullable `clockInAt`/`clockOutAt` parameters bolted onto
`markAttendance`. This matches the project's existing convention for
`AttendanceController` (`attachCheckInPhoto` / `attachBelongingsPhoto` are
separate methods, not one generic "update a column" call), and it keeps each
method's precondition explicit in its own signature rather than expressed as
"pass this param only sometimes."

```dart
// Creates today's row if none exists yet (or updates one a director already
// created for this teacher), setting status: 'present' and clock_in_at: now.
Future<StaffAttendance> clockIn({
  required String staffId,
  required String centerId,
  required String date,
  required String actorUid,
  String? existingId,
});

// Sets clock_out_at on an already-existing row. Never creates a row --
// clocking out with nothing to clock out of is a UI-level impossibility
// (the button only exists once a row exists), and the CHECK constraint above
// would reject clock_out_at with a null clock_in_at even if it were attempted.
Future<StaffAttendance> clockOut({
  required String id,
  required String actorUid,
});
```

`markAttendance` (from the previous spec) is untouched — still the method a
future director-marks-absent path uses.

## Screen

New file: `lib/features/profile/screens/staff_attendance_screen.dart`,
colocated with `change_password_screen.dart` and `person_detail_screen.dart`
— this project's existing convention for screens reached by pushing from
`ProfileScreen`.

```
Today · Wed 2 Sept
  Clocked in:  --:--          [ Clock in ]
  Clocked out: --:--
```

Tapping **Clock in** opens a confirmation dialog — *"Confirm clock-in at
14:32?"*, Cancel / Confirm — and only Confirm writes. Same shape for **Clock
out**, which appears once `clock_in_at` is set. Once both are set for today,
both buttons disappear; the two times render as plain read-only text and the
day is locked — no re-clocking in, no editing, in this task. Time is shown
24-hour (`14:32`), not 12-hour with AM/PM: this project has no `intl`
dependency (checked — grep found none, and no existing `DateFormat` usage
anywhere to mirror), and 24-hour avoids AM/PM ambiguity in a record meant to
be precise. A small formatter is added for it alongside the existing
`isoWithWeekday` in `lib/shared/util/date_display.dart`, in the same
hand-rolled style rather than pulling in a new package for one format string.

## Profile screen changes

- **Delete** `lib/features/profile/widgets/staff_attendance_toggle.dart` and
  its test file outright — this task replaces the chip toggle, not
  supplements it, per explicit instruction.
- **Remove** the `StaffAttendanceToggle` wiring from `profile_screen.dart`
  (the import and the widget instantiation added in the previous task).
- **Add** an "Attendance" `OutlinedButton.icon`, visible only when
  `user.role == 'teacher'`, in the same position the toggle occupied,
  `Navigator.push`ing `StaffAttendanceScreen` — identical pattern to the
  existing "Profile details" and "Change password" buttons on that screen.

## Testing

Same conventions as the previous spec: `StaffAttendanceController` gets no
dedicated unit test file (this project's actual, verified convention for
Supabase-backed controllers — proven only through the widget that consumes
it). The screen gets full TDD coverage:

- shows "Clock in" when nothing is recorded for today
- tapping Clock in shows a confirmation dialog with the current time, not an
  immediate write
- confirming calls `clockIn` with the signed-in user's own id and today's
  date; cancelling calls nothing
- after clocking in, shows the recorded time and a "Clock out" button
- confirming Clock out calls `clockOut` with the existing row's id
- after both are set, no buttons remain and both times render as text
- an error from either call surfaces a message, matching this project's
  existing SnackBar convention (`Could not clock in: $e` / `Could not clock
  out: $e`)

`profile_screen_test.dart` needs updating the same way the previous task
did: remove the `StaffAttendanceToggle`-related mock/override (no longer
referenced), and confirm the new "Attendance" button navigates to
`StaffAttendanceScreen` for a teacher and does not appear for a parent or
director.

The SQL migration itself is verified the same way as the previous spec's —
manually, since this project has no automated RLS/schema test suite
(verified in that spec; still true, this task adds no such suite): confirm
the `ALTER TABLE` applies cleanly, and that the CHECK constraint actually
rejects a clock-out-without-clock-in attempt.

## Open questions

None. Every design choice above traces to an explicit answer in this
conversation or an existing convention already verified in the codebase.
