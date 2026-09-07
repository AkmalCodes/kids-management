# Teacher attendance — two grids (teachers + children)

**Date:** 2026-09-07
**Status:** approved, not yet implemented

## Problem

Piece **C** of a three-part change (A: grid tile name label — shipped; B:
co-teachers on a class — shipped; C: this). Two things to fix:

1. The teacher's clock-in/out entry point is an "Attendance"
   `OutlinedButton.icon` bolted onto the shared `ProfileScreen`. It looks
   out of place there and the spacing fights the other profile buttons.
2. The teacher's attendance tab (`MarkAttendanceScreen`) shows only a grid
   of the children they teach. It should also show the teachers on their
   class(es) — themselves plus co-teachers (Piece B) — so the clock-in/out
   entry lives here, beside the people it concerns, and a teacher can see
   who they share a room with.

## Goals

- `MarkAttendanceScreen` shows two grids: **Teachers** then **Children**,
  separated by a labelled horizontal divider (`——— Teachers ———` /
  `——— Children ———`).
- Both grids use the same tile design as the current children grid —
  size-stable avatar, one-line `shortLabelName`, corner badge — with one
  difference: teacher avatars are **circular**, child avatars stay
  rounded-square.
- The signed-in teacher's own tile is first in the Teachers grid, carries a
  three-state clock badge, and opens the clock-in/out screen.
- Co-teacher tiles open that teacher's profile, read-only.
- The "Attendance" button is removed from `ProfileScreen`. The clock-in/out
  screen is now reached only from the Teachers grid.

## Non-goals

- Any change to `staff_attendance` or its RLS. A teacher still reads only
  their own clock rows; co-teacher tiles therefore carry no clock badge.
- Any change to `children.teacher_id`, the children query, or the child
  status-marking flow. The children grid is exactly as it is today.
- The director's attendance view (`director_attendance_screen`) and the
  parent views. `MarkAttendanceScreen` is teacher-only (`TeacherShell`);
  only teachers see the two-grid layout.
- A co-teacher being able to edit anything about another teacher. The
  profile view is read-only; the existing RLS already rejects the writes,
  this just removes the affordance.
- Search over the Teachers grid. Search stays children-only.

## Components

### `GridPersonTile` — new shared presentational widget

`lib/features/teacher/widgets/grid_person_tile.dart`. The current
`AttendanceGridTile` layout, generalised:

```dart
GridPersonTile({
  required Widget avatar,        // caller supplies the shaped avatar
  required String name,          // raw name; the tile applies shortLabelName
  Widget? badge,                 // optional; bottom-right, inset
  required VoidCallback onTap,
  VoidCallback? onLongPress,
})
```

- Column: `Expanded(Center(AspectRatio(1, Stack[avatar, Positioned badge])))`,
  then the fixed one-line name (`shortLabelName(name)`, `maxLines: 1`,
  `' '` fallback, `labelSmall` w600, centre). Identical to the
  Piece-A tile — the avatar stays the same size regardless of name length.
- `GridPersonTile` does **not** know about `Child`, `Attendance`,
  `AppUser`, circles, or squares. Callers pass a finished `avatar` widget
  and a finished `badge` widget.

### `AttendanceGridTile` — becomes a thin wrapper

`lib/features/teacher/widgets/attendance_grid_tile.dart` keeps its exact
public constructor (`child`, `attendance`, `onTap`, `onLongPress`) and its
`_photo` / `_placeholder` / `_badge` internals, but its `build` returns
`GridPersonTile(avatar: <the rounded-square ClipRRect photo + border>,
name: child.name, badge: _badge(colors), onTap: onTap, onLongPress:
onLongPress)`. No behaviour change; its existing tests stay green.

### `StaffGridTile` — new

`lib/features/teacher/widgets/staff_grid_tile.dart`:

```dart
StaffGridTile({
  required AppUser teacher,
  StaffClockState? clockState,  // null => no badge (co-teachers)
  required VoidCallback onTap,
})
```

- Wraps `GridPersonTile` with a **circular** avatar: a `CircleAvatar`-based
  widget over `signedAvatarUrlProvider(teacher.avatarPath)` when set, a
  person-icon placeholder otherwise. (`SignedAvatar` already does exactly
  this — reuse it; it is `CircleAvatar`-based by contract, which is what we
  want here, the opposite of why the child tile avoids it.)
- `clockState` is a 3-value enum:
  `StaffClockState { notClockedIn, working, done }`. Badge icons, distinct
  from the child present/absent/unmarked set:
  - `notClockedIn` → outline clock (`Icons.schedule`), amber
  - `working` → filled clock (`Icons.access_time_filled`), green
  - `done` → `Icons.logout` (arrow-out), muted / onSurfaceVariant
  Same badge container/inset as the child tile.
- `clockState == null` → no badge (used for every co-teacher tile).

### `MarkAttendanceScreen` — the two grids

`_load` gains two fetches beside the existing children + child-attendance:

- `fetchCoTeachers(user.id)` (Piece B, `TeacherController`).
- `staffAttendanceControllerProvider.fetchForDate(_today)` → find the
  signed-in user's own row → derive `StaffClockState`
  (`clock_out_at != null` → done; `clock_in_at != null` → working; else
  → notClockedIn).

`_RosterData` grows: `List<AppUser> teachers` (the signed-in user first,
then co-teachers by name), `StaffClockState myClockState`.

`build` swaps the single `GridView` for a `CustomScrollView`:

```
CustomScrollView
  SliverToBoxAdapter  -> _SectionDivider('Teachers')
  SliverPadding + SliverGrid  -> teacher tiles
       tile[0] (self): StaffGridTile(teacher: me, clockState: myClockState,
                        onTap: push StaffAttendanceScreen)
       tile[1..] (co-teachers): StaffGridTile(teacher: t, clockState: null,
                        onTap: push PersonDetailScreen(person: t, readOnly: true))
  SliverToBoxAdapter  -> _SectionDivider('Children')
  SliverPadding + SliverGrid  -> the existing AttendanceGridTile list,
       filtered by the existing search query, with the existing
       "No children assigned" / "No students match" empty text moved into
       a SliverToBoxAdapter
```

Grid delegate for both: the existing
`SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4,
crossAxisSpacing: 12, mainAxisSpacing: 16, childAspectRatio: 0.72)`.

The search + date header row (`Padding` above the old `Expanded`) is
unchanged and stays pinned above the `CustomScrollView`.

`_SectionDivider` is a small private widget: `Row[Expanded(Divider()),
Padding(Text(label uppercased, labelSmall, letter-spaced)),
Expanded(Divider())]`.

Own tile is always shown, even for a teacher with no `centerId` — tapping
it opens `StaffAttendanceScreen`, which already handles that precondition
itself. A teacher with no co-teachers simply sees a one-tile Teachers grid.

### `PersonDetailScreen` — `readOnly` mode

`PersonDetailScreen({required AppUser person, bool readOnly = false})`.
When `readOnly`:

- No AppBar Edit `IconButton`; `_editing` is forced false and can never flip.
- No "Change photo" affordance.
- View mode renders only **populated** rows: name and role always; phone,
  address, date of birth, emergency contact each only when non-null/
  non-empty. (Normal mode is unchanged — it still shows "Not provided"
  placeholders, because a director needs to see the gaps to fill them.)

`fetchCoTeachers` (Piece B) returns only id / role / name / phone /
center_id / avatar_path — the HR columns come back null — so in practice a
co-teacher view shows avatar, name, role, and phone if the teacher set one.

### `ProfileScreen`

Delete the `if (user.role == 'teacher') …` block containing the
"Attendance" `OutlinedButton.icon` and the `SizedBox(height: 12)` inside
it, plus the `import 'staff_attendance_screen.dart';`. Nothing else on that
screen moves.

## Data flow

`MarkAttendanceScreen._load` (one `Future`, as today) now awaits: current
user → then in parallel `childController.fetchForTeacher`,
`attendanceController.fetchForDate`, `teacherController.fetchCoTeachers`,
`staffAttendanceController.fetchForDate`. Assembles `_RosterData`
(`children`, `attendanceByChild`, `teachers`, `myClockState`). A clock-in
performed on the pushed `StaffAttendanceScreen` does not need to refresh
this screen live (matches today's behaviour for the child detail screen
before the grid-apply optimisation); the badge refreshes on the next
`_load`. If cheap, re-run `_load` in the `.then` of the
`StaffAttendanceScreen` push so the badge updates on return — decided in
the plan.

## Error handling

Same as the screen today: the `FutureBuilder` shows `AppLoader` until data,
then the grids. A failed `_load` currently falls through to
`!snapshot.hasData` → loader forever; that is a pre-existing behaviour and
out of scope here (Piece C adds no new error surface). The co-teacher and
staff-attendance fetches are additive awaits in the same `Future`; if one
throws, the whole `_load` rejects, same as a failing children fetch does
today.

## Testing

- **`GridPersonTile`** — widget TDD: renders `shortLabelName(name)` on one
  line; avatar slot is the same rendered size for a short and a very long
  name; the `badge` slot renders when given and is absent when null;
  `onTap` / `onLongPress` fire.
- **`StaffGridTile`** — widget TDD: uses a circular avatar (a
  `CircleAvatar` is present, unlike the child tile); each `StaffClockState`
  renders its distinct badge icon; `clockState: null` renders no badge;
  tap fires the callback. Override `signedAvatarUrlProvider` so no network.
- **`AttendanceGridTile`** — existing tests keep passing unchanged; add one
  asserting it now renders a `GridPersonTile` internally and still shows
  the status badge keys.
- **`MarkAttendanceScreen`** — new: the Teachers divider and Children
  divider both render; the signed-in teacher's own tile is first and shows
  the badge matching the mocked `staff_attendance` row
  (notClockedIn / working / done cases); a co-teacher from a mocked
  `fetchCoTeachers` renders with no badge; tapping own tile pushes
  `StaffAttendanceScreen`; tapping a co-teacher tile pushes
  `PersonDetailScreen` and that screen shows no Edit icon; the existing
  child-grid tests (search filter, mark present/absent, empty states) still
  pass with the layout change.
- **`PersonDetailScreen`** — new: `readOnly: true` hides the Edit
  `IconButton` and renders no "Not provided" rows for the null HR fields;
  `readOnly: false` (default) is unchanged.
- **`profile_screen_test`** — remove the two tests about the "Attendance"
  button (navigation + role visibility). No replacement — the entry point
  moved and is covered by the `MarkAttendanceScreen` tests.
- Full Flutter suite stays green; report the real count.

## Open questions

None.
