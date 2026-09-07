# Teacher Attendance Two-Grid Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `MarkAttendanceScreen` shows a **Teachers** grid (the signed-in teacher + co-teachers) above the existing **Children** grid, divided by labelled separators. The signed-in teacher's tile carries a 3-state clock badge and opens the clock-in/out screen; co-teacher tiles open a read-only profile. The "Attendance" button is removed from `ProfileScreen`.

**Architecture:** Extract the Piece-A tile layout into a shared `GridPersonTile`; `AttendanceGridTile` becomes a thin wrapper (rounded-square child photo), and a new `StaffGridTile` wraps it with a circular user avatar + clock badge. `MarkAttendanceScreen`'s body becomes a `CustomScrollView` of two `SliverGrid`s. `PersonDetailScreen` gains a `readOnly` flag.

**Tech Stack:** Flutter, Riverpod 2.x, mocktail.

**Spec:** `docs/superpowers/specs/2026-09-07-teacher-attendance-two-grids-design.md`

## Global Constraints

- Piece **C** of three (A: grid tile label, B: co-teachers — both shipped). Consumes `TeacherController.fetchCoTeachers` (Piece B) and `shortLabelName` (Piece A), both already on this branch.
- No change to `staff_attendance` / its RLS / `children.teacher_id` / the children query / the child status-marking flow. The children grid renders exactly as today; only its container changes (`GridView` → a `SliverGrid` inside a `CustomScrollView`).
- `MarkAttendanceScreen` is teacher-only (`TeacherShell`). Directors and parents are untouched.
- Teacher avatars are **circular** (`SignedAvatar` / `CircleAvatar`, `signedAvatarUrlProvider`, the user-avatars bucket). Child avatars stay rounded-square. `GridPersonTile` itself is shape-agnostic — the caller passes a finished `avatar` widget.
- Co-teacher tiles carry **no** badge (their clock rows aren't readable). Only the signed-in teacher's own tile has one.
- Grid delegate for both grids is the existing one: `SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 12, mainAxisSpacing: 16, childAspectRatio: 0.72)`.
- Search stays children-only. The Teachers grid is always shown in full.
- The signed-in teacher's own tile is always present and always first, even when `centerId` is null (tapping it opens `StaffAttendanceScreen`, which guards that itself).
- The full Flutter suite must stay green. Report the real count from `flutter test` output.
- Do not add a `Co-Authored-By` trailer to commits (repo convention — every prior commit on this branch has none).

---

### Task 1: `GridPersonTile` shared widget

The Piece-A tile layout, generalised. Pure presentational.

**Files:**
- Create: `lib/features/teacher/widgets/grid_person_tile.dart`
- Test: `test/features/teacher/widgets/grid_person_tile_test.dart`

**Interfaces:**
- Consumes: `shortLabelName` from `lib/shared/util/name_display.dart`.
- Produces: `GridPersonTile({required Widget avatar, required String name, Widget? badge, required VoidCallback onTap, VoidCallback? onLongPress})` — a `StatelessWidget`. Column: `Expanded(Center(AspectRatio(1, Stack(fit: expand, [avatar, if badge != null Positioned(right: 6, bottom: 6, child: badge)]))))`, `SizedBox(height: 6)`, then a one-line `Text(shortLabelName(name).isEmpty ? ' ' : shortLabelName(name), maxLines: 1, overflow: ellipsis, textAlign: center, style: labelSmall.copyWith(fontWeight: w600))`. Wrapped in `InkWell(onTap:, onLongPress:, borderRadius: BorderRadius.circular(16))`.

- [ ] **Step 1: Write the failing test**

Create `test/features/teacher/widgets/grid_person_tile_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/features/teacher/widgets/grid_person_tile.dart';

Future<void> _pump(
  WidgetTester tester, {
  required String name,
  Widget? badge,
  VoidCallback? onTap,
  VoidCallback? onLongPress,
}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 84,
            height: 117,
            child: GridPersonTile(
              avatar: const ColoredBox(color: Colors.blue),
              name: name,
              badge: badge,
              onTap: onTap ?? () {},
              onLongPress: onLongPress,
            ),
          ),
        ),
      ),
    ));

void main() {
  testWidgets('renders the shortened one-line name label', (tester) async {
    await _pump(tester, name: 'Ammar Ali Hassan');
    expect(find.text('Ammar H.'), findsOneWidget);
    expect(find.text('Ammar Ali Hassan'), findsNothing);
  });

  testWidgets('avatar slot is the same size for a short and a long name',
      (tester) async {
    await _pump(tester, name: 'Al');
    final short = tester.getSize(find.byType(AspectRatio));
    await _pump(tester, name: 'Muhammad Aariz Danish bin Abdul Rahman');
    final long = tester.getSize(find.byType(AspectRatio));
    expect(long, short);
  });

  testWidgets('renders the badge when given, omits it when null', (tester) async {
    await _pump(tester, name: 'Al', badge: const Icon(Icons.star, key: Key('b')));
    expect(find.byKey(const Key('b')), findsOneWidget);
    await _pump(tester, name: 'Al');
    expect(find.byKey(const Key('b')), findsNothing);
  });

  testWidgets('tap and long-press fire their callbacks', (tester) async {
    var taps = 0;
    var longs = 0;
    await _pump(tester, name: 'Al', onTap: () => taps++, onLongPress: () => longs++);
    await tester.tap(find.byType(GridPersonTile));
    await tester.pump();
    await tester.longPress(find.byType(GridPersonTile));
    await tester.pump();
    expect(taps, 1);
    expect(longs, 1);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/teacher/widgets/grid_person_tile_test.dart`
Expected: FAIL — cannot resolve `grid_person_tile.dart`.

- [ ] **Step 3: Write the widget**

Create `lib/features/teacher/widgets/grid_person_tile.dart`:

```dart
import 'package:flutter/material.dart';
import '../../../shared/util/name_display.dart';

// The shared attendance-grid tile shell: a size-stable square avatar slot
// with an optional inset corner badge, and a fixed one-line name beneath.
// Presentational only -- it knows nothing about Child / AppUser / circles /
// squares. Callers pass a finished `avatar` widget and a finished `badge`.
// AttendanceGridTile (children, rounded-square photo + status badge) and
// StaffGridTile (teachers, circular avatar + clock badge) both wrap this so
// the Piece-A "name length never changes the avatar size" behaviour stays
// identical for both.
class GridPersonTile extends StatelessWidget {
  const GridPersonTile({
    super.key,
    required this.avatar,
    required this.name,
    required this.onTap,
    this.badge,
    this.onLongPress,
  });

  final Widget avatar;
  final String name;
  final Widget? badge;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final label = shortLabelName(name);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    avatar,
                    if (badge != null)
                      Positioned(right: 6, bottom: 6, child: badge!),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label.isEmpty ? ' ' : label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/teacher/widgets/grid_person_tile_test.dart`
Expected: PASS — 4 tests.

- [ ] **Step 5: Analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/teacher/widgets/grid_person_tile.dart test/features/teacher/widgets/grid_person_tile_test.dart
git commit -m "feat: GridPersonTile shared attendance-grid tile shell"
```

---

### Task 2: `AttendanceGridTile` becomes a `GridPersonTile` wrapper

**Files:**
- Modify: `lib/features/teacher/widgets/attendance_grid_tile.dart`
- Modify: `test/features/teacher/widgets/attendance_grid_tile_test.dart`

**Interfaces:**
- Consumes: `GridPersonTile` (Task 1).
- Produces: no public change — `AttendanceGridTile({required Child child, required Attendance? attendance, required VoidCallback onTap, required VoidCallback onLongPress})` is unchanged. Its `build` now returns a `GridPersonTile`.

- [ ] **Step 1: Refactor `build`**

In `lib/features/teacher/widgets/attendance_grid_tile.dart`, replace the `build` method's returned tree. The `_photo`, `_placeholder`, and `_badge` methods stay exactly as they are. New `build`:

```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    return GridPersonTile(
      name: child.name,
      onTap: onTap,
      onLongPress: onLongPress,
      badge: _badge(colors),
      // The child avatar: a rounded square with a translucent border, the
      // photo clipped inside. Deliberately NOT a CircleAvatar (that bug is
      // what the border+ClipRRect here fixed) -- the circular variant is the
      // teacher tile's job.
      avatar: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colors.primary.withValues(alpha: 0.25),
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: _photo(colors, ref),
        ),
      ),
    );
  }
```

Add the import:

```dart
import 'grid_person_tile.dart';
```

Remove the now-unused `shortLabelName` import if `attendance_grid_tile.dart` had one (it did — the Piece-A change added `import '../../../shared/util/name_display.dart';`). `GridPersonTile` owns the label now. Run `flutter analyze` to confirm no unused import remains.

- [ ] **Step 2: Update the tile's tests**

`test/features/teacher/widgets/attendance_grid_tile_test.dart` — the existing tests should all still pass unchanged (name label, badge keys, no `CircleAvatar`, `AspectRatio` size stability, overflow, textScale). Add one:

```dart
  testWidgets('is built on the shared GridPersonTile', (tester) async {
    await _pump(tester);
    expect(find.byType(GridPersonTile), findsOneWidget);
  });
```

with `import 'package:kids_management/features/teacher/widgets/grid_person_tile.dart';` added.

- [ ] **Step 3: Run this tile's tests + analyze + full suite**

Run: `flutter test test/features/teacher/widgets/attendance_grid_tile_test.dart`
Expected: PASS — all, including the new one.

Run: `flutter analyze && flutter test`
Expected: `No issues found!` and all pass. Report the count.

- [ ] **Step 4: Commit**

```bash
git add lib/features/teacher/widgets/attendance_grid_tile.dart test/features/teacher/widgets/attendance_grid_tile_test.dart
git commit -m "refactor: AttendanceGridTile wraps GridPersonTile"
```

---

### Task 3: `StaffGridTile` + `StaffClockState`

**Files:**
- Create: `lib/features/teacher/widgets/staff_grid_tile.dart`
- Test: `test/features/teacher/widgets/staff_grid_tile_test.dart`

**Interfaces:**
- Consumes: `GridPersonTile` (Task 1); `AppUser`; `SignedAvatar` + `signedAvatarUrlProvider` from `lib/shared/widgets/signed_avatar.dart` / `lib/core/controllers/profile_controller.dart` (confirm the provider's import path when writing — it is the same provider `ProfileScreen` uses for its avatar).
- Produces:
  - `enum StaffClockState { notClockedIn, working, done }`
  - `StaffGridTile({required AppUser teacher, StaffClockState? clockState, required VoidCallback onTap})` — a `StatelessWidget` (or `ConsumerWidget` only if the avatar provider needs `ref`; `SignedAvatar` is itself a `ConsumerWidget`, so `StaffGridTile` can stay a plain `StatelessWidget`). Wraps `GridPersonTile` with `avatar: SignedAvatar(urlProvider: teacher.avatarPath == null ? null : signedAvatarUrlProvider(teacher.avatarPath!), radius: 40)` and `badge:` the icon for `clockState`, or `null` when `clockState` is null.

- [ ] **Step 1: Write the failing test**

Create `test/features/teacher/widgets/staff_grid_tile_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/core/models/app_user.dart';
import 'package:kids_management/features/teacher/widgets/staff_grid_tile.dart';

AppUser _teacher({String? avatarPath}) => AppUser(
  id: 't-1',
  role: 'teacher',
  name: 'Aisha Rahman',
  phone: '',
  centerId: 'center-1',
  avatarPath: avatarPath,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

Future<void> _pump(
  WidgetTester tester, {
  StaffClockState? clockState,
  VoidCallback? onTap,
}) =>
    tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 84,
              height: 117,
              child: StaffGridTile(
                teacher: _teacher(),
                clockState: clockState,
                onTap: onTap ?? () {},
              ),
            ),
          ),
        ),
      ),
    ));

void main() {
  testWidgets('uses a circular avatar (unlike the child tile)', (tester) async {
    await _pump(tester);
    expect(find.byType(CircleAvatar), findsOneWidget);
  });

  testWidgets('shows the short name label', (tester) async {
    await _pump(tester);
    expect(find.text('Aisha R.'), findsOneWidget);
  });

  testWidgets('each clock state renders its distinct badge icon', (tester) async {
    await _pump(tester, clockState: StaffClockState.notClockedIn);
    expect(find.byIcon(Icons.schedule), findsOneWidget);

    await _pump(tester, clockState: StaffClockState.working);
    expect(find.byIcon(Icons.access_time_filled), findsOneWidget);

    await _pump(tester, clockState: StaffClockState.done);
    expect(find.byIcon(Icons.logout), findsOneWidget);
  });

  testWidgets('no clockState renders no badge', (tester) async {
    await _pump(tester, clockState: null);
    expect(find.byIcon(Icons.schedule), findsNothing);
    expect(find.byIcon(Icons.access_time_filled), findsNothing);
    expect(find.byIcon(Icons.logout), findsNothing);
  });

  testWidgets('tap fires the callback', (tester) async {
    var taps = 0;
    await _pump(tester, onTap: () => taps++);
    await tester.tap(find.byType(StaffGridTile));
    await tester.pump();
    expect(taps, 1);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/teacher/widgets/staff_grid_tile_test.dart`
Expected: FAIL — cannot resolve `staff_grid_tile.dart`.

- [ ] **Step 3: Write the widget**

Create `lib/features/teacher/widgets/staff_grid_tile.dart`:

```dart
import 'package:flutter/material.dart';
import '../../../core/models/app_user.dart';
import '../../../core/controllers/profile_controller.dart';
import '../../../shared/widgets/signed_avatar.dart';
import 'grid_person_tile.dart';

// Where the signed-in teacher is in their working day, for the Teachers-grid
// badge. Derived from today's staff_attendance row, not a DB concept, so it
// lives here. Co-teacher tiles pass null (their clock rows aren't readable).
enum StaffClockState { notClockedIn, working, done }

// One teacher in the Teachers grid: a circular avatar + one-line name, and --
// for the signed-in teacher only -- a clock-state badge. Circular on purpose:
// the child tile is a rounded square, teachers read as people not classes.
class StaffGridTile extends StatelessWidget {
  const StaffGridTile({
    super.key,
    required this.teacher,
    required this.onTap,
    this.clockState,
  });

  final AppUser teacher;
  final StaffClockState? clockState;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GridPersonTile(
      name: teacher.name,
      onTap: onTap,
      badge: clockState == null ? null : _badge(Theme.of(context).colorScheme),
      avatar: SignedAvatar(
        urlProvider: teacher.avatarPath == null
            ? null
            : signedAvatarUrlProvider(teacher.avatarPath!),
      ),
    );
  }

  Widget _badge(ColorScheme colors) {
    final (icon, color) = switch (clockState!) {
      StaffClockState.notClockedIn => (Icons.schedule, Colors.amber.shade700),
      StaffClockState.working => (Icons.access_time_filled, Colors.green.shade600),
      StaffClockState.done => (Icons.logout, colors.onSurfaceVariant),
    };
    return Container(
      decoration: BoxDecoration(color: colors.surface, shape: BoxShape.circle),
      padding: const EdgeInsets.all(1),
      child: Icon(icon, size: 20, color: color),
    );
  }
}
```

(`signedAvatarUrlProvider` lives in `lib/core/controllers/profile_controller.dart` — the import line above is correct. Do not create a new provider.)

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/teacher/widgets/staff_grid_tile_test.dart`
Expected: PASS — 6 tests.

- [ ] **Step 5: Analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/teacher/widgets/staff_grid_tile.dart test/features/teacher/widgets/staff_grid_tile_test.dart
git commit -m "feat: StaffGridTile with a 3-state clock badge"
```

---

### Task 4: `PersonDetailScreen` read-only mode

**Files:**
- Modify: `lib/features/profile/person_detail_screen.dart`
- Modify: `test/features/profile/person_detail_screen_test.dart`

**Interfaces:**
- Produces: `PersonDetailScreen({required AppUser person, bool readOnly = false})`. `readOnly` defaults false — every existing call site is unchanged.

- [ ] **Step 1: Add the flag**

In `person_detail_screen.dart`:

- Add `final bool readOnly;` to the widget and `this.readOnly = false` to the constructor.
- In the AppBar `actions`, wrap the Edit `IconButton` so it is omitted entirely when `widget.readOnly`:

```dart
        actions: [
          if (!widget.readOnly)
            IconButton(
              icon: Icon(_editing ? Icons.close : Icons.edit_outlined),
              tooltip: _editing ? 'Cancel' : 'Edit',
              onPressed: _editing ? _cancelEdit : _startEdit,
            ),
        ],
```

- `_editing` starts false and, with no Edit button, can never become true in `readOnly` mode — so the "Change photo" affordance (already gated on `if (_editing)`) and the editable fields never appear. No further change needed there.
- The view-mode rows: today `_readOnlyRow` renders `'Not provided'` for empty values. In `readOnly` mode, skip a row entirely when its value is null/empty. The cleanest form: give `_readOnlyRow` a guard, or wrap each optional row's call site with `if (!widget.readOnly || <value>.isNotEmpty)`. Name and role rows always render. Phone, address, date of birth, emergency contact name, emergency contact phone each render only when non-empty **or** not in `readOnly` mode.

- [ ] **Step 2: Update the test**

In `test/features/profile/person_detail_screen_test.dart`, add:

```dart
  testWidgets('readOnly hides the Edit button and the "Not provided" rows',
      (tester) async {
    // A co-teacher-style AppUser: identity only, HR fields null.
    await pumpScreen(tester, person: _peerTeacher(), readOnly: true);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.text('Not provided'), findsNothing);
    expect(find.text(_peerTeacher().name), findsWidgets);
  });
```

Add a `_peerTeacher()` fixture (role `teacher`, `address`/`dob`/`emergencyContact*` all null) and give the file's `pumpScreen` helper an optional `bool readOnly = false` + `AppUser? person` that it forwards to `PersonDetailScreen`. Keep every existing test calling `pumpScreen(tester)` working (defaults unchanged).

- [ ] **Step 3: Run this screen's tests + analyze**

Run: `flutter test test/features/profile/person_detail_screen_test.dart`
Expected: PASS.

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/profile/person_detail_screen.dart test/features/profile/person_detail_screen_test.dart
git commit -m "feat: PersonDetailScreen readOnly mode"
```

---

### Task 5: `MarkAttendanceScreen` — the two grids

The real integration task.

**Files:**
- Modify: `lib/features/teacher/screens/mark_attendance_screen.dart`
- Modify: `test/features/teacher/screens/mark_attendance_screen_test.dart`

**Interfaces:**
- Consumes: `GridPersonTile` (1), `StaffGridTile` + `StaffClockState` (3), `PersonDetailScreen` with `readOnly` (4); `TeacherController.fetchCoTeachers` + `teacherControllerProvider`; `StaffAttendanceController.fetchForDate` + `staffAttendanceControllerProvider`; `StaffAttendanceScreen`.
- Produces: no public change to `MarkAttendanceScreen`.

- [ ] **Step 1: Write the failing tests**

In `test/features/teacher/screens/mark_attendance_screen_test.dart`:

Add mock classes and imports:

```dart
import 'package:kids_management/core/models/staff_attendance.dart';
import 'package:kids_management/core/controllers/teacher_controller.dart';
import 'package:kids_management/core/controllers/staff_attendance_controller.dart';
import 'package:kids_management/features/teacher/widgets/staff_grid_tile.dart';
import 'package:kids_management/features/profile/staff_attendance_screen.dart';
import 'package:kids_management/features/profile/person_detail_screen.dart';

class MockTeacherController extends Mock implements TeacherController {}
class MockStaffAttendanceController extends Mock implements StaffAttendanceController {}
```

In `setUp`, create the two new mocks and give every test a default so the existing child-grid tests keep working:

```dart
    mockTeacherCtl = MockTeacherController();
    mockStaffAtt = MockStaffAttendanceController();
    when(() => mockTeacherCtl.fetchCoTeachers(any())).thenAnswer((_) async => []);
    when(() => mockStaffAtt.fetchForDate(any())).thenAnswer((_) async => []);
```

Add both to `pumpScreen`'s `overrides`:

```dart
            teacherControllerProvider.overrideWithValue(mockTeacherCtl),
            staffAttendanceControllerProvider.overrideWithValue(mockStaffAtt),
```

New tests (add a `StaffAttendance` fixture helper `_staffRow({DateTime? clockInAt, DateTime? clockOutAt})` for `staffId: 'teacher-1'`, `date: <today>`, mirroring the one in `staff_attendance_screen_test.dart`):

```dart
  testWidgets('renders both section dividers', (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1')).thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => []);
    await pumpScreen(tester);
    await tester.pumpAndSettle();
    expect(find.text('TEACHERS'), findsOneWidget);
    expect(find.text('CHILDREN'), findsOneWidget);
  });

  testWidgets("the signed-in teacher's own tile is first and shows the clock badge",
      (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1')).thenAnswer((_) async => []);
    when(() => mockStaffAtt.fetchForDate(any())).thenAnswer(
      (_) async => [_staffRow(clockInAt: DateTime.utc(2026, 9, 7, 6, 30))],
    );
    await pumpScreen(tester);
    await tester.pumpAndSettle();
    // one StaffGridTile (self), badge = working (clocked in, not out)
    expect(find.byType(StaffGridTile), findsOneWidget);
    expect(find.byIcon(Icons.access_time_filled), findsOneWidget);
  });

  testWidgets('a co-teacher renders with no badge', (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1')).thenAnswer((_) async => []);
    when(() => mockTeacherCtl.fetchCoTeachers('teacher-1')).thenAnswer(
      (_) async => [_coTeacher('t-2', 'Ben Ng')],
    );
    await pumpScreen(tester);
    await tester.pumpAndSettle();
    expect(find.byType(StaffGridTile), findsNWidgets(2)); // self + co-teacher
    // self is notClockedIn (no row) -> Icons.schedule once; co-teacher -> none
    expect(find.byIcon(Icons.schedule), findsOneWidget);
  });

  testWidgets('tapping the own tile opens the clock-in/out screen', (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1')).thenAnswer((_) async => []);
    await pumpScreen(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(StaffGridTile).first);
    await tester.pumpAndSettle();
    expect(find.byType(StaffAttendanceScreen), findsOneWidget);
  });

  testWidgets('tapping a co-teacher tile opens their read-only profile', (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1')).thenAnswer((_) async => []);
    when(() => mockTeacherCtl.fetchCoTeachers('teacher-1')).thenAnswer(
      (_) async => [_coTeacher('t-2', 'Ben Ng')],
    );
    await pumpScreen(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(StaffGridTile).last);
    await tester.pumpAndSettle();
    expect(find.byType(PersonDetailScreen), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });
```

Add `_coTeacher(id, name)` returning an `AppUser` (role `teacher`, HR fields null). Keep the existing child-grid tests; they will need a child present now for the Children grid to render tiles, but their assertions about "No children assigned" / search / mark-present still hold — verify each still passes and adjust only if the two-grid layout genuinely moved a finder (e.g. an empty-children message now sits under the CHILDREN divider rather than filling the screen).

- [ ] **Step 2: Run to verify the new tests fail**

Run: `flutter test test/features/teacher/screens/mark_attendance_screen_test.dart`
Expected: FAIL — no `TEACHERS` divider, no `StaffGridTile`, etc.

- [ ] **Step 3: Implement the two grids**

In `lib/features/teacher/screens/mark_attendance_screen.dart`:

Add imports:

```dart
import '../../../core/models/app_user.dart';
import '../../../core/models/staff_attendance.dart';
import '../../../core/controllers/staff_attendance_controller.dart';
import '../../../core/controllers/teacher_controller.dart';
import '../widgets/staff_grid_tile.dart';
import '../../profile/staff_attendance_screen.dart';
import '../../profile/person_detail_screen.dart';
```

Grow `_RosterData`:

```dart
class _RosterData {
  const _RosterData({
    required this.children,
    required this.attendanceByChild,
    required this.teachers,        // signed-in teacher first, then co-teachers by name
    required this.myClockState,
  });
  final List<Child> children;
  final Map<String, Attendance> attendanceByChild;
  final List<AppUser> teachers;
  final StaffClockState myClockState;
}
```

`_load`:

```dart
  Future<_RosterData> _load() async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null) {
      return const _RosterData(
        children: [], attendanceByChild: {}, teachers: [],
        myClockState: StaffClockState.notClockedIn,
      );
    }
    final children = await ref.read(childControllerProvider).fetchForTeacher(user.id);
    final records = await ref.read(attendanceControllerProvider).fetchForDate(_today);
    final coTeachers = await ref.read(teacherControllerProvider).fetchCoTeachers(user.id);
    final staffRows = await ref.read(staffAttendanceControllerProvider).fetchForDate(_today);

    StaffAttendance? mine;
    for (final r in staffRows) {
      if (r.staffId == user.id) { mine = r; break; }
    }
    final myClockState = mine?.clockOutAt != null
        ? StaffClockState.done
        : mine?.clockInAt != null
            ? StaffClockState.working
            : StaffClockState.notClockedIn;

    return _RosterData(
      children: children,
      attendanceByChild: {for (final r in records) r.childId: r},
      teachers: [user, ...coTeachers],
      myClockState: myClockState,
    );
  }
```

`_applyUpdate` — add the two new fields when it rebuilds `_RosterData`:

```dart
      _future = Future.value(
        _RosterData(
          children: data.children,
          attendanceByChild: {...data.attendanceByChild, childId: updated},
          teachers: data.teachers,
          myClockState: data.myClockState,
        ),
      );
```

Add a tap handler for the teachers grid:

```dart
  Future<void> _openTeacher(AppUser me, AppUser teacher) async {
    if (teacher.id == me.id) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const StaffAttendanceScreen()),
      );
      // The clock screen has no onChanged callback; re-load so the own-tile
      // badge reflects a clock-in done while it was open.
      if (mounted) {
        setState(() {
          _future = _load();
        });
      }
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PersonDetailScreen(person: teacher, readOnly: true),
        ),
      );
    }
  }
```

Replace the `build`'s `Expanded(child: FutureBuilder(...))` body. Keep the header `Padding` row exactly as it is. The `FutureBuilder` builder becomes:

```dart
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: AppLoader());
              }
              final data = snapshot.data!;
              final me = data.teachers.isEmpty ? null : data.teachers.first;
              final filteredChildren = data.children
                  .where((c) => c.name.toLowerCase().contains(_query.toLowerCase()))
                  .toList();

              const gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
                childAspectRatio: 0.72,
              );

              return CustomScrollView(
                slivers: [
                  const SliverToBoxAdapter(child: _SectionDivider('Teachers')),
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverGrid(
                      gridDelegate: gridDelegate,
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final t = data.teachers[i];
                          return StaffGridTile(
                            teacher: t,
                            clockState: (me != null && t.id == me.id)
                                ? data.myClockState
                                : null,
                            onTap: () => _openTeacher(me!, t),
                          );
                        },
                        childCount: data.teachers.length,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: _SectionDivider('Children')),
                  if (data.children.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('No children assigned to you yet.')),
                      ),
                    )
                  else if (filteredChildren.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(child: Text('No students match "$_query".')),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverGrid(
                        gridDelegate: gridDelegate,
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final child = filteredChildren[i];
                            final existing = data.attendanceByChild[child.id];
                            return AttendanceGridTile(
                              child: child,
                              attendance: existing,
                              onTap: () => _openDetail(child, existing),
                              onLongPress: () => _showActions(child, existing),
                            );
                          },
                          childCount: filteredChildren.length,
                        ),
                      ),
                    ),
                ],
              );
            },
```

Add the private divider widget at the bottom of the file:

```dart
class _SectionDivider extends StatelessWidget {
  const _SectionDivider(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w600,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(label.toUpperCase(), style: style),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the screen's tests to verify they pass**

Run: `flutter test test/features/teacher/screens/mark_attendance_screen_test.dart`
Expected: PASS — new tests plus the pre-existing child-grid tests.

- [ ] **Step 5: Analyze + full suite**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` and all pass. Report the count.

- [ ] **Step 6: Commit**

```bash
git add lib/features/teacher/screens/mark_attendance_screen.dart test/features/teacher/screens/mark_attendance_screen_test.dart
git commit -m "feat: teachers grid above the children grid on the attendance page"
```

---

### Task 6: Remove the "Attendance" button from `ProfileScreen`

**Files:**
- Modify: `lib/features/profile/profile_screen.dart`
- Modify: `test/features/profile/profile_screen_test.dart`

- [ ] **Step 1: Delete the button**

In `lib/features/profile/profile_screen.dart`, remove the entire
`if (user.role == 'teacher') ...[ … ]` block that renders the "Attendance"
`OutlinedButton.icon` and its trailing `SizedBox(height: 12)`, and remove
`import 'staff_attendance_screen.dart';`. Nothing else on the screen moves.

- [ ] **Step 2: Update the test**

In `test/features/profile/profile_screen_test.dart`, delete the two tests
covering the Attendance button (the one that taps it and expects
`StaffAttendanceScreen`, and the one asserting a parent/director does not
see it). Remove the now-unused `staff_attendance_screen` import if present.
Leave every other test as is.

- [ ] **Step 3: Run this screen's tests + analyze + full suite**

Run: `flutter test test/features/profile/profile_screen_test.dart`
Expected: PASS.

Run: `flutter analyze && flutter test`
Expected: `No issues found!` and all pass. Report the count.

- [ ] **Step 4: Commit**

```bash
git add lib/features/profile/profile_screen.dart test/features/profile/profile_screen_test.dart
git commit -m "feat: drop the Attendance button from Profile; entry moved to the attendance grid"
```

---

### Task 7: Update the design docs

**Files:**
- Modify: `docs/superpowers/specs/2026-09-07-teacher-attendance-two-grids-design.md`
- Modify: `docs/superpowers/specs/2026-07-01-childcare-management-design.md`
- Modify: `lib/features/profile/staff_attendance_screen.dart` (doc comment only)

- [ ] **Step 1: Flip the spec status**

`2026-09-07-teacher-attendance-two-grids-design.md`:
`**Status:** approved, not yet implemented` → `**Status:** implemented 2026-09-07`.

- [ ] **Step 2: Update the main design spec**

`2026-07-01-childcare-management-design.md`, §6.3 Attendance: note that the
teacher's attendance tab now shows a **Teachers** grid (the signed-in
teacher + co-teachers from their class) above the **Children** grid,
divided by labelled separators; the signed-in teacher's tile carries a
clock-in/out badge and opens the clock screen; co-teacher tiles open a
read-only profile. Note that the clock-in/out entry point moved off the
Profile tab. Pointer to
`docs/superpowers/specs/2026-09-07-teacher-attendance-two-grids-design.md`.

- [ ] **Step 3: Fix the `StaffAttendanceScreen` doc comment**

`lib/features/profile/staff_attendance_screen.dart` — the header comment
says "reached from the Profile tab" and "ProfileScreen only shows the entry
button to a teacher". Update both: it is reached from the **Attendance**
tab's Teachers grid (tapping your own tile); the teacher-only gating is
now that the Teachers grid only exists on the teacher attendance screen.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-09-07-teacher-attendance-two-grids-design.md docs/superpowers/specs/2026-07-01-childcare-management-design.md lib/features/profile/staff_attendance_screen.dart
git commit -m "docs: record the two-grid teacher attendance page"
```

---

## Done when

- The teacher attendance tab shows a Teachers grid (own tile first, with a
  3-state clock badge; co-teachers after, no badge) above the Children
  grid, with `——— TEACHERS ———` / `——— CHILDREN ———` dividers.
- Tapping the own tile opens the clock-in/out screen; tapping a co-teacher
  opens their profile with no Edit button.
- The children grid — tiles, search, mark present/absent, empty states — is
  unchanged in behaviour.
- `ProfileScreen` has no "Attendance" button.
- `flutter analyze` is clean and the full suite passes (report the real count).
- No change to `staff_attendance`, its RLS, `children.teacher_id`, or the
  child-marking flow.
