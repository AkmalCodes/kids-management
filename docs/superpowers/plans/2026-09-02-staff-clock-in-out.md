# Staff Clock-In/Out Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A teacher taps **Clock in** at the start of their day and **Clock out** at the end, each behind a confirm step, from a dedicated Attendance screen on their Profile tab — replacing the Present/Absent chip toggle shipped by the previous plan.

**Architecture:** Additive schema change — two `TIMESTAMPTZ` columns plus a CHECK constraint on the existing `staff_attendance` table. Two new explicitly-named controller methods (`clockIn` / `clockOut`) alongside the untouched `markAttendance`, matching this project's `attachCheckInPhoto` / `attachBelongingsPhoto` convention of one method per precondition. A new full-screen `StaffAttendanceScreen` pushed from `ProfileScreen`, colocated with `change_password_screen.dart`. The old `StaffAttendanceToggle` widget and its test are deleted outright.

**Tech Stack:** PostgreSQL/Supabase (RLS unchanged), Flutter, Riverpod 2.x, mocktail.

**Spec:** `docs/superpowers/specs/2026-09-02-staff-clock-in-out-design.md`

## Global Constraints

- Additive only. `status`, `notes`, RLS, audit columns, and the child `attendance` table are all untouched. No RLS policy changes in this plan.
- The CHECK constraint `staff_attendance_clock_order` must make "clocked out before/without clocking in" a database-level impossibility: `CHECK (clock_out_at IS NULL OR (clock_in_at IS NOT NULL AND clock_out_at > clock_in_at))`.
- `clock_in_at` / `clock_out_at` are distinct from `created_at` / `updated_at` — never reuse the audit timestamps as clock times.
- Both actions require an explicit confirm dialog (Cancel / Confirm) before any write. An accidental tap must not record a time.
- Once both times are set for a day, both buttons disappear, the times render as read-only text, and the day is locked — no re-clocking, no editing, in this task.
- Time is displayed 24-hour (`14:32`). This project has **no `intl` dependency** (verified — no `DateFormat` usage anywhere). Add a hand-rolled formatter beside the existing `isoWithWeekday` in `lib/shared/util/date_display.dart`; do not add a package.
- `AppUser.centerId` is `String?` (nullable). `clockIn` requires a non-null `center_id`; the screen must treat a centerless teacher as "nothing to show," not a crash.
- This project has **no per-controller unit test file** for Supabase-backed controllers (verified — no `attendance_controller_test.dart`). `StaffAttendanceController` gets none; `flutter analyze` is its verification, its contract is proven by the screen's widget test.
- This project has **no automated RLS/schema test suite** (verified). The migration is verified by hand in the Supabase SQL editor.
- The full Flutter suite must stay green throughout. Report the real final count from `flutter test` output — do not assume arithmetic.
- Do not add a `Co-Authored-By` trailer to commits (repo convention, confirmed for this task).

---

### Task 1: Schema migration SQL

No automated test loop — SQL applied by hand in the Supabase dashboard, per this project's existing practice (see the previous plan's Task 1 and `docs/superpowers/specs/2026-08-07-security-hardening.sql`). Deliverable: the SQL file plus a manual verification walkthrough the user runs themselves.

**Files:**
- Create: `docs/superpowers/specs/2026-09-02-staff-clock-in-out.sql`

**Interfaces:**
- Consumes: the `staff_attendance` table from the previous plan.
- Produces: columns `clock_in_at TIMESTAMPTZ`, `clock_out_at TIMESTAMPTZ` and constraint `staff_attendance_clock_order` on that table. Task 2's `StaffAttendance.fromJson` reads exactly these column names.

- [ ] **Step 1: Write the migration SQL**

Create `docs/superpowers/specs/2026-09-02-staff-clock-in-out.sql`:

```sql
-- Staff clock-in/out: teachers record the real time they started and finished
-- work, feeding HR and (later) payroll. See the design spec at
-- docs/superpowers/specs/2026-09-02-staff-clock-in-out-design.md for the full
-- reasoning, including why these are separate columns from created_at/updated_at
-- and why the CHECK constraint is worth having.
--
-- Additive only: extends the staff_attendance table from
-- docs/superpowers/specs/2026-09-02-staff-attendance-schema.sql. Does not touch
-- status, RLS, or anything else about that table.
--
-- Run this once, by hand, in the Supabase SQL editor (Project -> SQL Editor).
-- Re-running will error on "column already exists" rather than silently
-- reapplying, so you'll know if it already ran.

ALTER TABLE staff_attendance
  ADD COLUMN clock_in_at  TIMESTAMPTZ,
  ADD COLUMN clock_out_at TIMESTAMPTZ,
  ADD CONSTRAINT staff_attendance_clock_order
    CHECK (clock_out_at IS NULL OR (clock_in_at IS NOT NULL AND clock_out_at > clock_in_at));
```

- [ ] **Step 2: Hand the user the file and the exact dashboard steps**

Tell the user, in these words or close to them:

> Open the Supabase dashboard for project `rpefksoutqsbreiyppee` → **SQL Editor** → **New query**. Paste the contents of `docs/superpowers/specs/2026-09-02-staff-clock-in-out.sql` and click **Run**. It should say `Success. No rows returned.`

- [ ] **Step 3: Give the user a manual verification walkthrough**

Hand the user this exact sequence (they run it, per this project's "user drives" convention). Each block is a separate query to paste into the SQL editor.

```sql
-- 1. Confirm the two columns exist.
select column_name, data_type
from information_schema.columns
where table_name = 'staff_attendance' and column_name in ('clock_in_at', 'clock_out_at');
```

Expected: two rows, both `timestamp with time zone`.

```sql
-- 2. The CHECK constraint must REJECT a clock-out with no clock-in.
--    Run as the service role (default) -- this is testing the constraint,
--    not RLS. Use any real staff_id + center_id from your profiles table.
insert into staff_attendance (staff_id, center_id, date, status, clock_out_at, created_by, updated_by)
values ('<any-teacher-uuid>', '<their-center-uuid>', date '1999-01-01', 'present',
        now(), '<any-teacher-uuid>', '<any-teacher-uuid>');
```

Expected: fails with `new row for relation "staff_attendance" violates check constraint "staff_attendance_clock_order"`.

```sql
-- 3. The CHECK constraint must REJECT clock_out_at <= clock_in_at.
insert into staff_attendance (staff_id, center_id, date, status, clock_in_at, clock_out_at, created_by, updated_by)
values ('<any-teacher-uuid>', '<their-center-uuid>', date '1999-01-01', 'present',
        now(), now() - interval '1 hour', '<any-teacher-uuid>', '<any-teacher-uuid>');
```

Expected: fails with the same check-constraint violation.

```sql
-- 4. A valid clock-in-then-out row is accepted.
insert into staff_attendance (staff_id, center_id, date, status, clock_in_at, clock_out_at, created_by, updated_by)
values ('<any-teacher-uuid>', '<their-center-uuid>', date '1999-01-01', 'present',
        now() - interval '8 hours', now(), '<any-teacher-uuid>', '<any-teacher-uuid>');
```

Expected: succeeds, one row.

```sql
-- 5. Cleanup: remove the test row.
delete from staff_attendance where date = date '1999-01-01';
```

- [ ] **Step 4: Confirm with the user that Steps 2 and 3 are done before proceeding**

Do not start Task 2 until the user confirms the columns exist and the CHECK constraint rejected at least the clock-out-without-clock-in case. If they hit an error, help debug it here.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/specs/2026-09-02-staff-clock-in-out.sql
git commit -m "docs: staff clock-in/out schema migration SQL"
```

---

### Task 2: `StaffAttendance` model — `clockInAt` / `clockOutAt`

Pure Dart, directly testable — no Supabase involved.

**Files:**
- Modify: `lib/core/models/staff_attendance.dart`
- Modify: `test/core/models/staff_attendance_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `StaffAttendance` gains `final DateTime? clockInAt;` and `final DateTime? clockOutAt;` (nullable, **not** `required` in the constructor — every existing call site passes all-named args and must keep compiling). `fromJson` parses `clock_in_at` / `clock_out_at`, tolerating `null`. `toJson` is **unchanged** — it is used only by the model test and by nothing that writes clock columns (Task 3's methods build their own payloads); adding write-only clock keys there is out of scope.

- [ ] **Step 1: Add the failing tests**

In `test/core/models/staff_attendance_test.dart`, add these two tests inside the existing `group('StaffAttendance', ...)`, after the `'fromJson defaults notes to empty string when absent'` test:

```dart
    test('fromJson parses clock_in_at and clock_out_at when present', () {
      final withClocks = Map<String, dynamic>.from(json)
        ..['clock_in_at'] = '2026-09-02T06:30:00.000Z'
        ..['clock_out_at'] = '2026-09-02T15:00:00.000Z';
      final record = StaffAttendance.fromJson(withClocks);
      expect(record.clockInAt, DateTime.utc(2026, 9, 2, 6, 30));
      expect(record.clockOutAt, DateTime.utc(2026, 9, 2, 15, 0));
    });

    test('fromJson leaves clock times null when the columns are null or absent', () {
      final withNulls = Map<String, dynamic>.from(json)
        ..['clock_in_at'] = null
        ..['clock_out_at'] = null;
      expect(StaffAttendance.fromJson(withNulls).clockInAt, isNull);
      expect(StaffAttendance.fromJson(withNulls).clockOutAt, isNull);
      // `json` itself has neither key -- absent must behave like null.
      expect(StaffAttendance.fromJson(json).clockInAt, isNull);
      expect(StaffAttendance.fromJson(json).clockOutAt, isNull);
    });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/core/models/staff_attendance_test.dart`
Expected: FAIL — `The getter 'clockInAt' isn't defined for the type 'StaffAttendance'`.

- [ ] **Step 3: Write the implementation**

Replace the whole of `lib/core/models/staff_attendance.dart` with:

```dart
import 'attendance.dart' show AttendanceStatus;

// A teacher's attendance for one day. Deliberately a separate table/model
// from Attendance (children) rather than a nullable child_id/staff_id on one
// shared table -- see docs/superpowers/specs/2026-09-02-staff-attendance-schema-design.md
// for why. No photo fields: the safety/handoff reasoning for child photos
// does not apply to staff.
class StaffAttendance {
  final String id;
  final String staffId;
  final String centerId;
  final String date; // YYYY-MM-DD
  final AttendanceStatus status;
  final String notes;
  // Real wall-clock times the teacher started/finished work, set by the
  // clock-in/out flow. Distinct from createdAt/updatedAt (row audit): a
  // future correction would touch updatedAt without changing when the person
  // actually clocked in. See
  // docs/superpowers/specs/2026-09-02-staff-clock-in-out-design.md.
  // Stored as TIMESTAMPTZ; parsed here as UTC, call .toLocal() to display.
  final DateTime? clockInAt;
  final DateTime? clockOutAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const StaffAttendance({
    required this.id,
    required this.staffId,
    required this.centerId,
    required this.date,
    required this.status,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
    this.clockInAt,
    this.clockOutAt,
  });

  factory StaffAttendance.fromJson(Map<String, dynamic> json) => StaffAttendance(
    id: json['id'] as String,
    staffId: json['staff_id'] as String,
    centerId: json['center_id'] as String,
    date: json['date'] as String,
    status: AttendanceStatus.values.firstWhere(
      (e) => e.name == (json['status'] as String),
    ),
    notes: json['notes'] as String? ?? '',
    clockInAt: json['clock_in_at'] == null
        ? null
        : DateTime.parse(json['clock_in_at'] as String),
    clockOutAt: json['clock_out_at'] == null
        ? null
        : DateTime.parse(json['clock_out_at'] as String),
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    createdBy: json['created_by'] as String?,
    updatedBy: json['updated_by'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'staff_id': staffId,
    'center_id': centerId,
    'date': date,
    'status': status.name,
    'notes': notes,
    'created_by': createdBy,
    'updated_by': updatedBy,
  };
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/core/models/staff_attendance_test.dart`
Expected: PASS — 6 tests.

- [ ] **Step 5: Run analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/core/models/staff_attendance.dart test/core/models/staff_attendance_test.dart
git commit -m "feat: clock_in_at/clock_out_at on StaffAttendance"
```

---

### Task 3: `StaffAttendanceController` — `clockIn` / `clockOut`

No dedicated unit test file (see Global Constraints). `flutter analyze` is this task's verification; the contract is proven by Task 5's widget test.

**Files:**
- Modify: `lib/core/controllers/staff_attendance_controller.dart`

**Interfaces:**
- Consumes: `StaffAttendance` (Task 2), `AttendanceStatus` (existing), the existing `SupabaseClient _client`.
- Produces two new methods on `StaffAttendanceController`:
  - `Future<StaffAttendance> clockIn({required String staffId, required String centerId, required String date, required String actorUid, String? existingId})` — `existingId` absent → insert a new row with `status: 'present'`, `clock_in_at: <now, UTC ISO-8601>`; `existingId` present → update that row (a director may have pre-created it), setting the same fields, preserving the original `created_by`. Returns the written row.
  - `Future<StaffAttendance> clockOut({required String id, required String actorUid})` — updates the row identified by `id`, setting `clock_out_at: <now, UTC ISO-8601>` and `updated_by`. Never inserts.
  - `markAttendance` and `fetchForDate` are untouched.

- [ ] **Step 1: Write the implementation**

Replace the whole of `lib/core/controllers/staff_attendance_controller.dart` with:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_controller.dart';
import '../models/attendance.dart';
import '../models/staff_attendance.dart';

class StaffAttendanceController {
  final SupabaseClient _client;

  StaffAttendanceController({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // All staff rows for a date, unfiltered by staff -- mirrors
  // AttendanceController.fetchForDate. A director's future roster view
  // fetches once and filters client-side by staff_id, same pattern
  // mark_attendance_screen.dart already uses for children.
  Future<List<StaffAttendance>> fetchForDate(String date) async {
    final rows = await _client.from('staff_attendance').select().eq('date', date);
    return (rows as List)
        .map((row) => StaffAttendance.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  // existingId absent -> insert; existingId present -> update, preserving
  // the original created_by. Same pattern as AttendanceController.markAttendance,
  // minus photo-column preservation -- there are no photo columns here.
  Future<StaffAttendance> markAttendance({
    required String staffId,
    required String centerId,
    required String date,
    required AttendanceStatus status,
    required String actorUid,
    String? existingId,
    String notes = '',
  }) async {
    final payload = {
      'staff_id': staffId,
      'center_id': centerId,
      'date': date,
      'status': status.name,
      'notes': notes,
      'updated_by': actorUid,
      if (existingId == null) 'created_by': actorUid,
    };
    final row = existingId != null
        ? await _client.from('staff_attendance').update(payload).eq('id', existingId).select().single()
        : await _client.from('staff_attendance').insert(payload).select().single();
    return StaffAttendance.fromJson(row);
  }

  // Records the start of a teacher's working day. Creates today's row if none
  // exists yet, or updates one a director already created for this teacher
  // (existingId). Sets status 'present' and clock_in_at = now. A separate,
  // explicitly named method rather than nullable params on markAttendance --
  // matches this project's attachCheckInPhoto/attachBelongingsPhoto convention
  // and keeps the precondition ("no clock time recorded yet") in the signature.
  Future<StaffAttendance> clockIn({
    required String staffId,
    required String centerId,
    required String date,
    required String actorUid,
    String? existingId,
  }) async {
    // UTC ISO-8601 -- Postgres TIMESTAMPTZ stores an absolute instant; the UI
    // calls .toLocal() when it displays the time.
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final payload = {
      'staff_id': staffId,
      'center_id': centerId,
      'date': date,
      'status': AttendanceStatus.present.name,
      'clock_in_at': nowIso,
      'updated_by': actorUid,
      if (existingId == null) 'created_by': actorUid,
    };
    final row = existingId != null
        ? await _client.from('staff_attendance').update(payload).eq('id', existingId).select().single()
        : await _client.from('staff_attendance').insert(payload).select().single();
    return StaffAttendance.fromJson(row);
  }

  // Records the end of the day. Only ever updates an existing row -- clocking
  // out with nothing to clock out of is a UI-level impossibility (the button
  // only exists once a row with clock_in_at exists), and the DB CHECK
  // constraint would reject clock_out_at with a null clock_in_at anyway.
  Future<StaffAttendance> clockOut({
    required String id,
    required String actorUid,
  }) async {
    final row = await _client
        .from('staff_attendance')
        .update({
          'clock_out_at': DateTime.now().toUtc().toIso8601String(),
          'updated_by': actorUid,
        })
        .eq('id', id)
        .select()
        .single();
    return StaffAttendance.fromJson(row);
  }
}

final staffAttendanceControllerProvider = Provider<StaffAttendanceController>(
  (ref) => StaffAttendanceController(client: ref.watch(supabaseClientProvider)),
);
```

- [ ] **Step 2: Run analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Run the full suite (nothing should have broken)**

Run: `flutter test`
Expected: same pass count as before this task — no test references `clockIn`/`clockOut` yet.

- [ ] **Step 4: Commit**

```bash
git add lib/core/controllers/staff_attendance_controller.dart
git commit -m "feat: clockIn/clockOut on StaffAttendanceController"
```

---

### Task 4: `hourMinute` time formatter

A one-line pure function beside `isoWithWeekday`. Gets its own test cycle because it is trivially unit-testable and the screen (Task 5) depends on it.

**Files:**
- Modify: `lib/shared/util/date_display.dart`
- Create: `test/shared/util/date_display_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `String hourMinute(DateTime d)` → zero-padded 24-hour `HH:mm` of `d` as-is (caller passes an already-`.toLocal()`ed `DateTime`). E.g. `hourMinute(DateTime(2026, 9, 2, 6, 5))` → `'06:05'`.

- [ ] **Step 1: Write the failing test**

Create `test/shared/util/date_display_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/shared/util/date_display.dart';

void main() {
  group('hourMinute', () {
    test('zero-pads hours and minutes to HH:mm', () {
      expect(hourMinute(DateTime(2026, 9, 2, 6, 5)), '06:05');
    });

    test('uses 24-hour clock, no AM/PM', () {
      expect(hourMinute(DateTime(2026, 9, 2, 14, 32)), '14:32');
      expect(hourMinute(DateTime(2026, 9, 2, 0, 0)), '00:00');
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/shared/util/date_display_test.dart`
Expected: FAIL — `The function 'hourMinute' isn't defined`.

- [ ] **Step 3: Write the implementation**

Append to `lib/shared/util/date_display.dart`:

```dart

// 24-hour `HH:mm` for a DateTime, e.g. 06:05 or 14:32. Hand-rolled on
// purpose: this project has no `intl` dependency and pulling one in for a
// single format string isn't worth it. Caller passes an already-localised
// DateTime (`.toLocal()`); this does no timezone conversion.
String hourMinute(DateTime d) {
  final h = d.hour.toString().padLeft(2, '0');
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/shared/util/date_display_test.dart`
Expected: PASS — 2 tests.

- [ ] **Step 5: Run analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/shared/util/date_display.dart test/shared/util/date_display_test.dart
git commit -m "feat: hourMinute 24-hour time formatter"
```

---

### Task 5: `StaffAttendanceScreen`, wired into `ProfileScreen`; delete the toggle

The real TDD task. Builds the screen, swaps the Profile wiring from the deleted toggle to an "Attendance" button, and updates `profile_screen_test.dart`.

**Files:**
- Create: `lib/features/profile/staff_attendance_screen.dart`
- Delete: `lib/features/profile/widgets/staff_attendance_toggle.dart`
- Delete: `test/features/profile/widgets/staff_attendance_toggle_test.dart`
- Modify: `lib/features/profile/profile_screen.dart`
- Create: `test/features/profile/staff_attendance_screen_test.dart`
- Modify: `test/features/profile/profile_screen_test.dart`

**Interfaces:**
- Consumes: `StaffAttendanceController` (Task 3) via `staffAttendanceControllerProvider`; `hourMinute` (Task 4), `isoWithWeekday` (existing) from `lib/shared/util/date_display.dart`; `currentUserProvider`, `AppUser` (existing); `AppLoader` (existing).
- Produces: `StaffAttendanceScreen({super.key})` — a `ConsumerStatefulWidget` with its own `Scaffold` + `AppBar(title: Text('Attendance'))`, no constructor parameters (reads the signed-in user itself, like `ProfileScreen`).

- [ ] **Step 1: Write the failing test**

Create `test/features/profile/staff_attendance_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kids_management/core/auth/auth_controller.dart';
import 'package:kids_management/core/models/app_user.dart';
import 'package:kids_management/core/models/attendance.dart';
import 'package:kids_management/core/models/staff_attendance.dart';
import 'package:kids_management/core/controllers/staff_attendance_controller.dart';
import 'package:kids_management/features/profile/staff_attendance_screen.dart';

class MockStaffAttendanceController extends Mock implements StaffAttendanceController {}

AppUser _teacher({String? centerId = 'center-1'}) => AppUser(
  id: 'teacher-1',
  role: 'teacher',
  name: 'Alice',
  phone: '',
  centerId: centerId,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

StaffAttendance _row({DateTime? clockInAt, DateTime? clockOutAt}) => StaffAttendance(
  id: 'sa-1',
  staffId: 'teacher-1',
  centerId: 'center-1',
  date: '2026-09-02',
  status: AttendanceStatus.present,
  notes: '',
  clockInAt: clockInAt,
  clockOutAt: clockOutAt,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'teacher-1',
  updatedBy: 'teacher-1',
);

void main() {
  late MockStaffAttendanceController mockController;

  setUp(() {
    mockController = MockStaffAttendanceController();
  });

  Future<void> pump(WidgetTester tester, {AppUser? user}) => tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => Stream.value(user ?? _teacher())),
            staffAttendanceControllerProvider.overrideWithValue(mockController),
          ],
          child: const MaterialApp(home: StaffAttendanceScreen()),
        ),
      );

  void stubClockIn(StaffAttendance result) {
    when(() => mockController.clockIn(
          staffId: any(named: 'staffId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
        )).thenAnswer((_) async => result);
  }

  void stubClockOut(StaffAttendance result) {
    when(() => mockController.clockOut(
          id: any(named: 'id'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => result);
  }

  testWidgets('shows a Clock in button when nothing is recorded for today',
      (tester) async {
    when(() => mockController.fetchForDate(any())).thenAnswer((_) async => []);

    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Clock in'), findsOneWidget);
    expect(find.text('Clock out'), findsNothing);
  });

  testWidgets('tapping Clock in opens a confirm dialog and does not write yet',
      (tester) async {
    when(() => mockController.fetchForDate(any())).thenAnswer((_) async => []);

    await pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Clock in'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('Confirm clock-in at'), findsOneWidget);
    verifyNever(() => mockController.clockIn(
          staffId: any(named: 'staffId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
        ));
  });

  testWidgets('cancelling the confirm dialog writes nothing', (tester) async {
    when(() => mockController.fetchForDate(any())).thenAnswer((_) async => []);

    await pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Clock in'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => mockController.clockIn(
          staffId: any(named: 'staffId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
        ));
  });

  testWidgets('confirming Clock in calls clockIn with the signed-in id, today, no existingId',
      (tester) async {
    when(() => mockController.fetchForDate(any())).thenAnswer((_) async => []);
    stubClockIn(_row(clockInAt: DateTime.utc(2026, 9, 2, 6, 30)));

    await pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Clock in'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    verify(() => mockController.clockIn(
          staffId: 'teacher-1',
          centerId: 'center-1',
          date: any(named: 'date'),
          actorUid: 'teacher-1',
          existingId: null,
        )).called(1);
  });

  testWidgets('confirming Clock in passes existingId when a row already exists',
      (tester) async {
    // A director pre-created today's row (status absent, no clock times).
    when(() => mockController.fetchForDate(any()))
        .thenAnswer((_) async => [_row()]);
    stubClockIn(_row(clockInAt: DateTime.utc(2026, 9, 2, 6, 30)));

    await pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Clock in'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    verify(() => mockController.clockIn(
          staffId: 'teacher-1',
          centerId: 'center-1',
          date: any(named: 'date'),
          actorUid: 'teacher-1',
          existingId: 'sa-1',
        )).called(1);
  });

  testWidgets('after clocking in, shows the recorded time and a Clock out button',
      (tester) async {
    when(() => mockController.fetchForDate(any())).thenAnswer(
      (_) async => [_row(clockInAt: DateTime.utc(2026, 9, 2, 6, 30))],
    );

    await pump(tester);
    await tester.pumpAndSettle();

    final localHhmm = _hhmm(DateTime.utc(2026, 9, 2, 6, 30).toLocal());
    expect(find.textContaining(localHhmm), findsWidgets);
    expect(find.widgetWithText(FilledButton, 'Clock out'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Clock in'), findsNothing);
  });

  testWidgets('confirming Clock out calls clockOut with the existing row id',
      (tester) async {
    when(() => mockController.fetchForDate(any())).thenAnswer(
      (_) async => [_row(clockInAt: DateTime.utc(2026, 9, 2, 6, 30))],
    );
    stubClockOut(_row(
      clockInAt: DateTime.utc(2026, 9, 2, 6, 30),
      clockOutAt: DateTime.utc(2026, 9, 2, 15, 0),
    ));

    await pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Clock out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    verify(() => mockController.clockOut(id: 'sa-1', actorUid: 'teacher-1')).called(1);
  });

  testWidgets('once both times are set, no buttons remain and both render as text',
      (tester) async {
    when(() => mockController.fetchForDate(any())).thenAnswer(
      (_) async => [
        _row(
          clockInAt: DateTime.utc(2026, 9, 2, 6, 30),
          clockOutAt: DateTime.utc(2026, 9, 2, 15, 0),
        ),
      ],
    );

    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.byType(FilledButton), findsNothing);
    expect(find.textContaining(_hhmm(DateTime.utc(2026, 9, 2, 6, 30).toLocal())), findsWidgets);
    expect(find.textContaining(_hhmm(DateTime.utc(2026, 9, 2, 15, 0).toLocal())), findsWidgets);
  });

  testWidgets('an error from clockIn surfaces a message', (tester) async {
    when(() => mockController.fetchForDate(any())).thenAnswer((_) async => []);
    when(() => mockController.clockIn(
          staffId: any(named: 'staffId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
        )).thenThrow(Exception('network down'));

    await pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Clock in'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not clock in'), findsOneWidget);
  });

  testWidgets('an error from clockOut surfaces a message', (tester) async {
    when(() => mockController.fetchForDate(any())).thenAnswer(
      (_) async => [_row(clockInAt: DateTime.utc(2026, 9, 2, 6, 30))],
    );
    when(() => mockController.clockOut(
          id: any(named: 'id'),
          actorUid: any(named: 'actorUid'),
        )).thenThrow(Exception('network down'));

    await pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Clock out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not clock out'), findsOneWidget);
  });

  testWidgets('shows nothing to clock when the teacher has no center', (tester) async {
    await pump(tester, user: _teacher(centerId: null));
    await tester.pumpAndSettle();

    expect(find.byType(FilledButton), findsNothing);
  });
}

// Local mirror of lib/shared/util/date_display.dart's hourMinute, so the test
// asserts on the same string the screen renders without importing the widget's
// own helper indirectly.
String _hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/profile/staff_attendance_screen_test.dart`
Expected: FAIL — cannot resolve `package:kids_management/features/profile/staff_attendance_screen.dart`.

- [ ] **Step 3: Write the screen**

Create `lib/features/profile/staff_attendance_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/staff_attendance.dart';
import '../../core/controllers/staff_attendance_controller.dart';
import '../../shared/util/date_display.dart';
import '../../shared/widgets/app_loader.dart';

// A teacher's clock-in / clock-out for today, reached from the Profile tab.
// Replaces the old Present/Absent chip toggle: the recorded times feed HR and
// (later) payroll, so each write goes behind a confirm step and, once both
// times are set, the day is locked -- no re-clocking, no editing here. See
// docs/superpowers/specs/2026-09-02-staff-clock-in-out-design.md.
//
// ProfileScreen only shows the entry button to a teacher; the centerId guard
// lives here because it is this screen's own precondition (clockIn needs a
// non-null center_id), not a question of who may see the button.
class StaffAttendanceScreen extends ConsumerStatefulWidget {
  const StaffAttendanceScreen({super.key});

  @override
  ConsumerState<StaffAttendanceScreen> createState() => _StaffAttendanceScreenState();
}

class _StaffAttendanceScreenState extends ConsumerState<StaffAttendanceScreen> {
  // Captured once, like mark_attendance_screen.dart's _today: a clock action
  // taken right before midnight must target the day that was on screen when
  // it built, not whatever "today" becomes mid-tap.
  final DateTime _todayDate = DateTime.now();
  late final String _today = _todayDate.toIso8601String().substring(0, 10);

  late Future<StaffAttendance?> _record;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _record = _load();
  }

  Future<StaffAttendance?> _load() async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null || user.role != 'teacher' || user.centerId == null) return null;
    final all = await ref.read(staffAttendanceControllerProvider).fetchForDate(_today);
    // fetchForDate returns every staff member's row for the day -- keep only
    // this user's own.
    for (final row in all) {
      if (row.staffId == user.id) return row;
    }
    return null;
  }

  Future<bool> _confirm(String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _clockIn(StaffAttendance? existing) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null || user.centerId == null) return;
    if (!await _confirm('Confirm clock-in at ${hourMinute(DateTime.now())}?')) return;
    setState(() => _busy = true);
    try {
      final updated = await ref.read(staffAttendanceControllerProvider).clockIn(
            staffId: user.id,
            centerId: user.centerId!,
            date: _today,
            actorUid: user.id,
            existingId: existing?.id,
          );
      if (!mounted) return;
      setState(() {
        _record = Future.value(updated);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not clock in: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clockOut(StaffAttendance existing) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;
    if (!await _confirm('Confirm clock-out at ${hourMinute(DateTime.now())}?')) return;
    setState(() => _busy = true);
    try {
      final updated = await ref.read(staffAttendanceControllerProvider).clockOut(
            id: existing.id,
            actorUid: user.id,
          );
      if (!mounted) return;
      setState(() {
        _record = Future.value(updated);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not clock out: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: FutureBuilder<StaffAttendance?>(
        future: _record,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: AppLoader());
          }
          final row = snapshot.data;
          final clockedIn = row?.clockInAt != null;
          final clockedOut = row?.clockOutAt != null;
          // A null row means "nothing recorded yet" for a normal teacher, but
          // _load also returns null for a teacher with no center_id -- and
          // clockIn requires one. Gate the Clock in button on it so a
          // centerless teacher sees the times (all --:--) but no dead button.
          final canClockIn =
              ref.watch(currentUserProvider).value?.centerId != null;

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Today', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(
                isoWithWeekday(_today),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),
              _TimeRow(
                label: 'Clocked in',
                value: clockedIn ? hourMinute(row!.clockInAt!.toLocal()) : '--:--',
              ),
              const SizedBox(height: 8),
              _TimeRow(
                label: 'Clocked out',
                value: clockedOut ? hourMinute(row!.clockOutAt!.toLocal()) : '--:--',
              ),
              const SizedBox(height: 24),
              if (!clockedIn && canClockIn)
                FilledButton(
                  onPressed: _busy ? null : () => _clockIn(row),
                  child: const Text('Clock in'),
                )
              else if (clockedIn && !clockedOut)
                FilledButton(
                  onPressed: _busy ? null : () => _clockOut(row!),
                  child: const Text('Clock out'),
                ),
              // Both set -> no button; the day is locked and the two _TimeRows
              // above already show the recorded times as plain text.
            ],
          );
        },
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyLarge),
        Text(value, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the screen test to verify it passes**

Run: `flutter test test/features/profile/staff_attendance_screen_test.dart`
Expected: PASS — 12 tests. (The `canClockIn` guard in `build` is what makes the "no center" test pass: `_load` returns null for a centerless teacher, same as "nothing recorded yet", so the button is gated on the signed-in user's `centerId` directly.)

- [ ] **Step 5: Delete the old toggle and its test**

```bash
git rm lib/features/profile/widgets/staff_attendance_toggle.dart test/features/profile/widgets/staff_attendance_toggle_test.dart
```

- [ ] **Step 6: Rewire `ProfileScreen`**

In `lib/features/profile/profile_screen.dart`:

Replace the import line:

```dart
import 'widgets/staff_attendance_toggle.dart';
```

with:

```dart
import 'staff_attendance_screen.dart';
```

Replace this line:

```dart
            const StaffAttendanceToggle(),
```

with:

```dart
            if (user.role == 'teacher') ...[
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StaffAttendanceScreen()),
                ),
                icon: const Icon(Icons.schedule_outlined),
                label: const Text('Attendance'),
              ),
              const SizedBox(height: 12),
            ],
```

(The old toggle sat directly after the Role `_InfoTile` and before `const SizedBox(height: 24)`; this button takes the same slot. The `SizedBox(height: 12)` inside the block matches the spacing between the other `OutlinedButton.icon`s on this screen; the existing `SizedBox(height: 24)` after it stays.)

- [ ] **Step 7: Update `profile_screen_test.dart`**

The existing file already mocks `staffAttendanceControllerProvider` and stubs `fetchForDate` (added by the previous task). Two changes:

1. It still imports nothing of the toggle, so no import to remove. Confirm there is **no** `staff_attendance_toggle` import — if one exists, delete it.

2. Add a test that the new button appears for a teacher and navigates, and does not appear for a non-teacher. Add these inside `main()`, after the `'signs out when Sign out is tapped'` test:

```dart
  testWidgets('a teacher sees an Attendance button that opens StaffAttendanceScreen',
      (tester) async {
    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Attendance'));
    await tester.pumpAndSettle();

    expect(find.byType(StaffAttendanceScreen), findsOneWidget);
  });

  testWidgets('a non-teacher does not see the Attendance button', (tester) async {
    await pumpScreen(tester, role: 'parent');
    await tester.pumpAndSettle();

    expect(find.text('Attendance'), findsNothing);
  });
```

3. For the second test, `pumpScreen` needs to accept a `role`. Update the helper and the `_user` factory in this file:

Change `_user`:

```dart
AppUser _user({String? avatarPath, String role = 'teacher'}) => AppUser(
  id: 'uid-1',
  role: role,
  name: 'Alice',
  phone: '',
  centerId: 'center-1',
  avatarPath: avatarPath,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);
```

Change `pumpScreen`'s signature and the `currentUserProvider` override:

```dart
  Future<void> pumpScreen(WidgetTester tester, {String? avatarPath, String role = 'teacher'}) async {
```

```dart
          currentUserProvider.overrideWith((ref) => Stream.value(_user(avatarPath: avatarPath, role: role))),
```

Add the import:

```dart
import 'package:kids_management/features/profile/staff_attendance_screen.dart';
```

- [ ] **Step 8: Run both profile test files**

Run: `flutter test test/features/profile/`
Expected: PASS. `profile_screen_test.dart` gains 2 tests; `staff_attendance_toggle_test.dart` is gone; `staff_attendance_screen_test.dart` contributes 12.

- [ ] **Step 9: Run analyze and the full suite**

Run: `flutter analyze`
Expected: `No issues found!` (a leftover reference to `StaffAttendanceToggle` anywhere will show here.)

Run: `flutter test`
Expected: `All tests passed!`. Report the real count.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat: teacher clock-in/out screen replaces the attendance toggle"
```

---

### Task 6: Update the design docs

**Files:**
- Modify: `docs/superpowers/specs/2026-09-02-staff-clock-in-out-design.md`
- Modify: `docs/superpowers/specs/2026-07-01-childcare-management-design.md`

- [ ] **Step 1: Flip the spec status**

In `docs/superpowers/specs/2026-09-02-staff-clock-in-out-design.md`, change:

```markdown
**Status:** approved, not yet implemented
```

to:

```markdown
**Status:** implemented 2026-09-02
```

Add one line under the Screen section noting the actual file path shipped at `lib/features/profile/staff_attendance_screen.dart` (not a `screens/` subdir — colocated with `change_password_screen.dart`, matching how `profile_screen.dart` imports its pushed screens).

- [ ] **Step 2: Update the main design spec**

In `docs/superpowers/specs/2026-07-01-childcare-management-design.md`, near the `staff_attendance` schema entry added by the previous plan, add: `staff_attendance` now also carries `clock_in_at` / `clock_out_at` (`TIMESTAMPTZ`, nullable) with a CHECK constraint enforcing `clock_out_at > clock_in_at`; a teacher sets them via **Profile → Attendance** (`StaffAttendanceScreen`), each behind a confirm step, and a day locks once both are set. Pointer to `docs/superpowers/specs/2026-09-02-staff-clock-in-out-design.md` for the reasoning.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-09-02-staff-clock-in-out-design.md docs/superpowers/specs/2026-07-01-childcare-management-design.md
git commit -m "docs: record staff clock-in/out as implemented"
```

---

## Done when

- The user has run the migration SQL and confirmed the CHECK constraint rejects a clock-out-without-clock-in.
- `flutter analyze` is clean and the full suite passes (report the real count).
- A signed-in teacher sees **Profile → Attendance**; the screen shows **Clock in**, then after a confirm step shows the recorded time and **Clock out**, then after a second confirm shows both times as locked read-only text.
- A parent or director sees no Attendance button.
- `StaffAttendanceToggle` and its test no longer exist; nothing references them.
- The child `attendance` table, `markAttendance`, `fetchForDate`, and all RLS are unchanged.
