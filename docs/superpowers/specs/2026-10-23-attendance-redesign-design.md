# Attendance redesign — direction AA "Arrival board"

**Date:** 2026-10-23
**Status:** approved (design AA in Figma, page "Screen designs", frames AA1–AA6)

## Problem

The attendance screens (teacher, director, parent) work but look dated and
don't fit how the centre actually runs mornings: children **trickle in over
about an hour**, and the teacher takes a **check-in photo for almost every
child** as they arrive. Marking one child today means: tap tile → detail
screen → pick status → tap photo slot → menu → camera. The director only sees
children (not teachers), and parents land on a plain history list when what
they want is "did my child arrive, and how do they look today?".

Decisions from brainstorming (2026-10-22/23):

- Scope: look **plus workflow shortcuts on existing data**. No schema changes
  (security hardening of existing policies is separate, see below).
- Teacher flow is arrival-driven and photo-first.
- Director sees **teachers and children**, and can **fix teachers'**
  attendance (status, notes, fill in a missing clock time). Children stay
  read-only for the director (decision from the 2026-09-02 staff spec).
- Parent opens to **today's check-in** (reassurance), history below.
- Recorded clock times stay immutable from the app — fixing a *wrong*
  recorded time is a policy change, not part of this work.

## Design (AA)

### Teacher — Attendance tab (AA1)

- Header: date ("Thursday, 23 Oct"), the class name (or "Your children" when
  the teacher's children span several classes), search toggle.
- Three counts: **Here** (present + late), **Waiting** (no record today),
  **Absent** (absent + excused).
- **Teachers** row: the existing tiles (own tile → clock screen with clock
  badge; co-teachers → read-only profile).
- **Waiting** grid: dashed, faded tiles with "Check in". Tap → camera opens
  → check-in sheet (AA2). "Mark the rest…" (only when someone is waiting)
  asks to confirm, then marks every waiting child absent.
- **Here** grid: tiles with a green badge and arrival time; **Absent** grid
  (only if any): red badge. Tap either → the same sheet, pre-filled.
- Arrival time = the attendance row's `created_at` (the first mark of the
  day). Accurate because teachers mark on arrival.
- The long-press quick menu is removed (the sheet makes it redundant).

### Teacher — check-in sheet (AA2), replaces ChildAttendanceDetailScreen

One bottom sheet for checking a child in and for changing them later.

- Header: avatar, name, class, **allergies** in red when set (safety: this
  was on the old detail screen).
- Check-in photo: the photo just taken (local preview), or the saved one;
  "Retake" / "Take photo". Opening the sheet from a Waiting tile opens the
  camera first; cancelling the camera still opens the sheet (photo optional).
- Status: Present / Late / Absent / Excused segmented control.
- Belongings photo and note: optional, one tap each.
- Primary button: "Check in Nurul" for a new record, "Save" for an existing
  one. Save = `markAttendance` (status + notes), then upload/attach any new
  photo(s). The sheet stays open with an error if any step fails.

### Teacher — clock in/out (AA3), restyled StaffAttendanceScreen

- Hero card: hours worked today (or "Not clocked in yet"), state pill.
- Two rows: Clock in / Clock out with times and a lock once recorded.
- One primary button for the next action (Clock in → Clock out → none),
  keeping the existing confirm step.
- "This week": the teacher's own rows Mon–today (new read-only fetch,
  `StaffAttendanceController.fetchForStaffBetween`, own rows only — already
  allowed by `staff_attendance_select`).

### Director — Attendance tab (AA4)

- Header with date picker; **Children | Teachers** switch.
- Children: counts, a red banner listing teachers not clocked in (tap →
  Teachers), class filter chips, then one section per class: "BUNGA · 8 OF
  14 HERE" with small avatar tiles (badge = status, dashed = waiting). Tap →
  read-only sheet (status, photos, notes).
- Teachers: list of every teacher with clock in/out times and status. Tap →
  fix sheet: set status + notes; "Record clock-in/out" at a chosen time only
  where it is still empty (existing guarded `clockIn` / `clockOut`).

### Parent — Attendance tab (AA5) and one day (AA6)

- Child chips when the parent has more than one child.
- Today card: check-in photo, status pill with arrival time, "<name> is at
  school" (or "Not checked in yet" / "Absent today").
- This week: Mon–Fri dots (status colours; today ringed).
- Earlier: one card per past day → AA6 (status, check-in photo, belongings
  photo, teacher's note), restyled AttendanceDetailScreen.

## Security

Authorisation lives in Postgres RLS; the app hiding a button is not a
control. Every write this redesign uses:

| Write | Who | Policy |
|---|---|---|
| `attendance` insert/update (status, notes) | teacher, own class | `attendance_insert` / `attendance_update` |
| `attendance-photos` upload | teacher, own class | `attendance_photos_teacher_insert/update` |
| `staff_attendance` clock in/out | teacher, own row | `staff_attendance_insert/update` |
| `staff_attendance` status/notes/missing times | director, own centre | `staff_attendance_insert/update` |

Gaps found in the documented policies (to be confirmed against the live
database, then fixed with SQL the user runs — handoff
`2026-10-23-attendance-rls-hardening.sql`):

1. **Clock times are only immutable in the app.** `staff_attendance_update`
   lets a teacher update their own row with no column limits, so a direct
   API call can rewrite `clock_in_at` / `clock_out_at` (payroll data). Fix: a
   trigger that rejects changing a clock time once set, and rejects a
   teacher changing anything but their own clock-in/out-when-null.
2. **`attendance_update` has no WITH CHECK beyond `created_by`**: a teacher
   can repoint their row at another child or centre. Fix: WITH CHECK that the
   child is still in their class and `created_by` is still them.
3. **`attendance_insert` doesn't pin `created_by`** to the caller. Fix: add
   `created_by = auth.uid()` to the WITH CHECK.
4. Co-teacher limitation (functional, not a hole): `attendance_update`
   requires `created_by = me`, so a co-teacher cannot change a record their
   colleague created. Left as is; noted for a later decision.

## Build order

Each step is its own commit with tests:

1. Teacher board + check-in sheet (AA1, AA2); ChildAttendanceDetailScreen removed.
2. Clock screen (AA3) + `fetchForStaffBetween`.
3. Director tab (AA4) with read-only child sheet and teacher fix sheet.
4. Parent tab and day detail (AA5, AA6).
5. RLS hardening SQL handoff + verification queries (user runs in dashboard).

## Testing

Widget tests per screen with mocked controllers (existing pattern):
grouping into waiting/here/absent, counts, the check-in save sequence
(mark → upload → attach), "Mark the rest" confirm, director fix only offering
"record" for empty times, parent today card states, 360px overflow checks.
