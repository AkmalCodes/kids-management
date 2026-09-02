# Staff Attendance Schema Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A teacher can mark their own daily attendance; a director can (in a later task) mark any teacher's. This plan lays the table, RLS, model, controller, and one small real control to prove it end to end.

**Architecture:** A new `staff_attendance` table, shaped like `attendance` minus photos. RLS mirrors the existing self/director split used everywhere else in this schema. `StaffAttendance`/`StaffAttendanceController` mirror `Attendance`/`AttendanceController`'s method shapes exactly, so anyone who already knows the child-attendance code reads this one for free. A new self-contained `StaffAttendanceToggle` widget — not a restructure of the shared `ProfileScreen` — is the only UI, shown to teachers only.

**Tech Stack:** PostgreSQL/Supabase (RLS), Flutter, Riverpod 2.x, mocktail.

**Spec:** `docs/superpowers/specs/2026-09-02-staff-attendance-schema-design.md`

## Global Constraints

- `child_id` attendance stays completely untouched. Directors still cannot mark child attendance — this was explicitly decided against. No task in this plan touches `attendance`, `attendance_insert`, or `attendance_update`.
- `staff_attendance` scope: teachers only. No photos. `status`/`notes`/audit columns match `attendance`'s shape.
- RLS: a teacher may only read/insert/update their **own** row (`staff_id = auth.uid()`). A director may read/insert/update any row where the target `staff_id` is a teacher **in the director's own center** (`center_id = my_center()`), never cross-center.
- Reuse the existing `my_center()` SECURITY DEFINER helper. Do not write a new one.
- **This project has no automated RLS test suite** (verified: no pgTAP, no policy-test file anywhere in the repo). RLS is verified manually, by the user, in the Supabase SQL editor. Do not invent a testing framework as a side effect of this feature.
- **This project has no per-controller unit test file for Supabase-backed controllers either** (verified: no `attendance_controller_test.dart` exists; `AttendanceController` is exercised only through the widget tests of the screens that use it, with the controller mocked at its own interface). `StaffAttendanceController` follows the same convention — no bare unit test file. Its contract is proven by the widget test in Task 4.
- `StaffAttendance`'s own `fromJson`/`toJson` **are** unit-testable pure Dart, exactly as `Attendance`'s are (`test/core/models/attendance_test.dart` exists and is the pattern to mirror) — that part does get a dedicated test.
- `AppUser.centerId` is `String?` (nullable). The toggle must not call `markAttendance` when it is null — handle it as "nothing to show," not a crash.
- The full Flutter suite (226 tests going into this plan) must stay green throughout.
- Do not add a `Co-Authored-By` trailer to commits.

---

### Task 1: Schema and RLS

This task has no automated test loop — it is SQL applied by hand in the Supabase dashboard, per this project's existing practice for schema changes (see `docs/mailgun-porkbun-domain-setup.md`'s "user drives" pattern and `docs/superpowers/specs/2026-08-07-security-hardening.sql`, which is a doc file the user ran, not a CLI migration). The deliverable is the SQL file plus a manual verification walkthrough for the user to run themselves.

**Files:**
- Create: `docs/superpowers/specs/2026-09-02-staff-attendance-schema.sql`

**Interfaces:**
- Consumes: nothing.
- Produces: the `staff_attendance` table, columns `id, staff_id, center_id, date, status, notes, created_at, updated_at, created_by, updated_by`. Later tasks' `StaffAttendance.fromJson` reads exactly these column names.

- [ ] **Step 1: Write the migration SQL**

Create `docs/superpowers/specs/2026-09-02-staff-attendance-schema.sql`:

```sql
-- Staff attendance: teachers mark their own daily attendance; directors mark
-- any teacher's, scoped to their own center. See the design spec at
-- docs/superpowers/specs/2026-09-02-staff-attendance-schema-design.md for the
-- full reasoning, including why this is a separate table from `attendance`
-- and why directors were deliberately NOT given the ability to mark child
-- attendance in this same pass.
--
-- Run this once, by hand, in the Supabase SQL editor (Project -> SQL Editor).
-- Idempotent-ish: re-running will error on "table already exists" rather than
-- silently duplicating, so you'll know if it already ran.

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

ALTER TABLE staff_attendance ENABLE ROW LEVEL SECURITY;

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

- [ ] **Step 2: Hand the user the file and the exact dashboard steps**

Tell the user, in these words or close to them:

> Open the Supabase dashboard for project `rpefksoutqsbreiyppee` → **SQL Editor** → **New query**. Paste the contents of `docs/superpowers/specs/2026-09-02-staff-attendance-schema.sql` and click **Run**. It should say `Success. No rows returned.`

- [ ] **Step 3: Give the user a manual verification walkthrough**

Hand the user this exact sequence (they run it, per this project's "user drives" convention — see the memory note `feedback_user_drives_claude_guides`). Each block is a separate query to paste into the SQL editor. Between blocks, tell them what to look for.

First, find two real ids to test with — a teacher and a director in the *same* center, and (if one exists) a teacher in a *different* center:

```sql
select id, role, center_id, name from profiles where role in ('teacher', 'director') order by center_id, role;
```

Then, **as the teacher** (Supabase SQL editor runs as the service role by default, so impersonation needs the `set local role` + `request.jwt.claims` trick — walk the user through whichever of these two your Supabase project version supports; try block A first):

```sql
-- Block A: impersonate a specific user via their JWT claims
select set_config('request.jwt.claims', json_build_object('sub', '<teacher-uuid>', 'role', 'authenticated')::text, true);
insert into staff_attendance (staff_id, center_id, date, status, created_by, updated_by)
values ('<teacher-uuid>', '<their-center-uuid>', current_date, 'present', '<teacher-uuid>', '<teacher-uuid>');
```

Expected: succeeds, one row.

```sql
-- The same teacher trying to mark a DIFFERENT teacher -- must fail
select set_config('request.jwt.claims', json_build_object('sub', '<teacher-uuid>', 'role', 'authenticated')::text, true);
insert into staff_attendance (staff_id, center_id, date, status, created_by, updated_by)
values ('<a-different-teacher-uuid>', '<their-center-uuid>', current_date, 'present', '<teacher-uuid>', '<teacher-uuid>');
```

Expected: fails with a row-level security policy violation.

```sql
-- The director in the SAME center marking that teacher -- must succeed
select set_config('request.jwt.claims', json_build_object('sub', '<director-uuid>', 'role', 'authenticated')::text, true);
insert into staff_attendance (staff_id, center_id, date, status, created_by, updated_by)
values ('<a-different-teacher-uuid>', '<their-center-uuid>', current_date, 'present', '<director-uuid>', '<director-uuid>')
on conflict (staff_id, date) do update set status = excluded.status;
```

Expected: succeeds.

```sql
-- A director marking a teacher in a DIFFERENT center -- must fail
-- (only run this if a teacher in a different center exists)
select set_config('request.jwt.claims', json_build_object('sub', '<director-uuid>', 'role', 'authenticated')::text, true);
insert into staff_attendance (staff_id, center_id, date, status, created_by, updated_by)
values ('<other-center-teacher-uuid>', '<other-center-uuid>', current_date, 'present', '<director-uuid>', '<director-uuid>');
```

Expected: fails.

```sql
-- Cleanup: remove the test rows this walkthrough created
select set_config('request.jwt.claims', null, true); -- drop back to service role
delete from staff_attendance where date = current_date and notes = '';
```

Tell the user: if `set_config`/`request.jwt.claims` doesn't behave as expected in their SQL editor (some Supabase project configurations differ), the fallback is testing through the app itself once Task 4 lands — mark your own attendance as a teacher, confirm it saves, and that is real proof the self-marking policy works. Full director-marks-teacher coverage will get its own proof once the director UI exists in a later plan.

- [ ] **Step 4: Confirm with the user that Step 2 and Step 3 are done before proceeding**

Do not start Task 2 until the user confirms the table exists and at least the self-marking case (a teacher can insert their own row, cannot insert another's) has been verified. If they hit an error, help them debug it here — a broken table blocks every later task.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/specs/2026-09-02-staff-attendance-schema.sql
git commit -m "docs: staff_attendance schema and RLS migration SQL"
```

---

### Task 2: `StaffAttendance` model

Pure Dart, directly testable — no Supabase involved.

**Files:**
- Create: `lib/core/models/staff_attendance.dart`
- Test: `test/core/models/staff_attendance_test.dart`

**Interfaces:**
- Consumes: `AttendanceStatus` from `lib/core/models/attendance.dart` (reused, not duplicated — it is a shared enum, not child-specific).
- Produces:
  - `StaffAttendance` with fields `id, staffId, centerId, date, status, notes, createdAt, updatedAt, createdBy, updatedBy` — same names/types as `Attendance` minus the two photo fields and with `staffId` instead of `childId`.
  - `StaffAttendance.fromJson(Map<String, dynamic>)`
  - `.toJson()` — omits `id` (matches `Attendance.toJson`'s convention: the id is never sent back on write, Supabase assigns/keeps it).

- [ ] **Step 1: Write the failing test**

Create `test/core/models/staff_attendance_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/core/models/attendance.dart';
import 'package:kids_management/core/models/staff_attendance.dart';

void main() {
  group('StaffAttendance', () {
    final json = {
      'id': 'sa-1',
      'staff_id': 'teacher-1',
      'center_id': 'center-1',
      'date': '2026-09-02',
      'status': 'present',
      'notes': '',
      'created_at': '2026-09-02T00:00:00.000Z',
      'updated_at': '2026-09-02T00:00:00.000Z',
      'created_by': 'teacher-1',
      'updated_by': 'teacher-1',
    };

    test('fromJson parses status enum from string', () {
      final record = StaffAttendance.fromJson(json);
      expect(record.staffId, 'teacher-1');
      expect(record.centerId, 'center-1');
      expect(record.date, '2026-09-02');
      expect(record.status, AttendanceStatus.present);
      expect(record.createdBy, 'teacher-1');
    });

    test('toJson serializes status enum as its name and omits id', () {
      final record = StaffAttendance.fromJson(json);
      final out = record.toJson();
      expect(out['status'], 'present');
      expect(out['staff_id'], 'teacher-1');
      expect(out.containsKey('id'), isFalse);
    });

    test('fromJson handles each AttendanceStatus value', () {
      for (final status in AttendanceStatus.values) {
        final withStatus = Map<String, dynamic>.from(json)..['status'] = status.name;
        expect(StaffAttendance.fromJson(withStatus).status, status);
      }
    });

    test('fromJson defaults notes to empty string when absent', () {
      final withoutNotes = Map<String, dynamic>.from(json)..remove('notes');
      expect(StaffAttendance.fromJson(withoutNotes).notes, '');
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/models/staff_attendance_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'kids_management/core/models/staff_attendance.dart'` (the file does not exist yet).

- [ ] **Step 3: Write the implementation**

Create `lib/core/models/staff_attendance.dart`:

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

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/models/staff_attendance_test.dart`
Expected: PASS — 4 tests.

- [ ] **Step 5: Run analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/core/models/staff_attendance.dart test/core/models/staff_attendance_test.dart
git commit -m "feat: StaffAttendance model"
```

---

### Task 3: `StaffAttendanceController`

No dedicated unit test file for this task — see Global Constraints for why. `flutter analyze` is this task's own verification; its contract gets proven by Task 4's widget test, which mocks this controller's interface exactly as `mark_attendance_screen_test.dart` mocks `AttendanceController`.

**Deliberate deviation from the design spec:** the spec's App Layer section lists `fetchForStaff(staffId)` (a per-staff history fetch, mirroring `AttendanceController.fetchForChild`) alongside `fetchForDate` and `markAttendance`. It is dropped here. Nothing in this plan's UI (Task 4's toggle needs only "does today have a record," answered by `fetchForDate` + a client-side filter) calls it, and an unused method is dead code, not a mirror worth having yet. Add it in whichever future task first needs a staff member's attendance history — likely the director's People/Attendance merge.

**Files:**
- Create: `lib/core/controllers/staff_attendance_controller.dart`

**Interfaces:**
- Consumes: `StaffAttendance` (Task 2), `AttendanceStatus` (existing), `supabaseClientProvider` (existing, from `core/auth/auth_controller.dart`).
- Produces:
  - `StaffAttendanceController({SupabaseClient? client})`
  - `Future<List<StaffAttendance>> fetchForDate(String date)` — all staff rows for a date, unfiltered by staff — mirrors `AttendanceController.fetchForDate` exactly. (Task 4 fetches once and filters client-side for the signed-in user's own id, the same pattern `mark_attendance_screen.dart` uses to build `attendanceByChild` from one `fetchForDate` call.)
  - `Future<StaffAttendance> markAttendance({required String staffId, required String centerId, required String date, required AttendanceStatus status, required String actorUid, String? existingId, String notes = ''})` — insert-or-update on `existingId`, same shape as `AttendanceController.markAttendance` minus the photo-preservation comment (there are no photo columns to preserve).
  - `final staffAttendanceControllerProvider = Provider<StaffAttendanceController>(...)`

- [ ] **Step 1: Write the implementation**

Create `lib/core/controllers/staff_attendance_controller.dart`:

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
}

final staffAttendanceControllerProvider = Provider<StaffAttendanceController>(
  (ref) => StaffAttendanceController(client: ref.watch(supabaseClientProvider)),
);
```

- [ ] **Step 2: Run analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/core/controllers/staff_attendance_controller.dart
git commit -m "feat: StaffAttendanceController"
```

---

### Task 4: `StaffAttendanceToggle` widget, wired into `ProfileScreen`

The real TDD task, and the one that proves Tasks 2-3's contract.

**Files:**
- Create: `lib/features/profile/widgets/staff_attendance_toggle.dart`
- Modify: `lib/features/profile/profile_screen.dart`
- Test: `test/features/profile/widgets/staff_attendance_toggle_test.dart`
- Modify: `test/features/profile/profile_screen_test.dart`

**Interfaces:**
- Consumes: `StaffAttendanceController` (Task 3) via `staffAttendanceControllerProvider`; `currentUserProvider`, `AppUser` (existing).
- Produces: `StaffAttendanceToggle({super.key})` — a `ConsumerStatefulWidget` with no constructor parameters; it reads the signed-in user itself, same as `ProfileScreen` does.

- [ ] **Step 1: Write the failing test**

Create `test/features/profile/widgets/staff_attendance_toggle_test.dart`:

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
import 'package:kids_management/features/profile/widgets/staff_attendance_toggle.dart';

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

StaffAttendance _saved(AttendanceStatus status) => StaffAttendance(
  id: 'sa-1',
  staffId: 'teacher-1',
  centerId: 'center-1',
  date: '2026-09-02',
  status: status,
  notes: '',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'teacher-1',
  updatedBy: 'teacher-1',
);

void main() {
  setUpAll(() {
    registerFallbackValue(AttendanceStatus.present);
  });

  late MockStaffAttendanceController mockController;

  setUp(() {
    mockController = MockStaffAttendanceController();
  });

  Future<void> pumpToggle(WidgetTester tester, {AppUser? user}) => tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => Stream.value(user ?? _teacher())),
            staffAttendanceControllerProvider.overrideWithValue(mockController),
          ],
          child: const MaterialApp(home: Scaffold(body: StaffAttendanceToggle())),
        ),
      );

  testWidgets('shows Present and Absent choices when nothing is marked yet',
      (tester) async {
    when(() => mockController.fetchForDate(any())).thenAnswer((_) async => []);

    await pumpToggle(tester);
    await tester.pumpAndSettle();

    expect(find.text('Present'), findsOneWidget);
    expect(find.text('Absent'), findsOneWidget);
  });

  testWidgets('reflects an existing record for today', (tester) async {
    when(() => mockController.fetchForDate(any()))
        .thenAnswer((_) async => [_saved(AttendanceStatus.present)]);

    await pumpToggle(tester);
    await tester.pumpAndSettle();

    final presentChip = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('Present'), matching: find.byType(ChoiceChip)),
    );
    expect(presentChip.selected, isTrue);
  });

  testWidgets('only shows this staff member\'s own record, not another teacher\'s',
      (tester) async {
    // fetchForDate returns every staff member's row -- the widget must
    // filter to its own before deciding what is selected.
    final other = StaffAttendance(
      id: 'sa-2',
      staffId: 'someone-else',
      centerId: 'center-1',
      date: '2026-09-02',
      status: AttendanceStatus.absent,
      notes: '',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      createdBy: 'someone-else',
      updatedBy: 'someone-else',
    );
    when(() => mockController.fetchForDate(any())).thenAnswer((_) async => [other]);

    await pumpToggle(tester);
    await tester.pumpAndSettle();

    final presentChip = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('Present'), matching: find.byType(ChoiceChip)),
    );
    final absentChip = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('Absent'), matching: find.byType(ChoiceChip)),
    );
    expect(presentChip.selected, isFalse);
    expect(absentChip.selected, isFalse);
  });

  testWidgets('tapping Present calls markAttendance with the signed-in user\'s own id',
      (tester) async {
    when(() => mockController.fetchForDate(any())).thenAnswer((_) async => []);
    when(() => mockController.markAttendance(
          staffId: any(named: 'staffId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          status: any(named: 'status'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
          notes: any(named: 'notes'),
        )).thenAnswer((_) async => _saved(AttendanceStatus.present));

    await pumpToggle(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();

    verify(() => mockController.markAttendance(
          staffId: 'teacher-1',
          centerId: 'center-1',
          date: any(named: 'date'),
          status: AttendanceStatus.present,
          actorUid: 'teacher-1',
          existingId: null,
        )).called(1);
  });

  testWidgets('marking again updates the same row via existingId', (tester) async {
    when(() => mockController.fetchForDate(any()))
        .thenAnswer((_) async => [_saved(AttendanceStatus.present)]);
    when(() => mockController.markAttendance(
          staffId: any(named: 'staffId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          status: any(named: 'status'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
          notes: any(named: 'notes'),
        )).thenAnswer((_) async => _saved(AttendanceStatus.absent));

    await pumpToggle(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Absent'));
    await tester.pumpAndSettle();

    verify(() => mockController.markAttendance(
          staffId: 'teacher-1',
          centerId: 'center-1',
          date: any(named: 'date'),
          status: AttendanceStatus.absent,
          actorUid: 'teacher-1',
          existingId: 'sa-1',
        )).called(1);
  });

  testWidgets('shows an error message when saving fails', (tester) async {
    when(() => mockController.fetchForDate(any())).thenAnswer((_) async => []);
    when(() => mockController.markAttendance(
          staffId: any(named: 'staffId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          status: any(named: 'status'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
          notes: any(named: 'notes'),
        )).thenThrow(Exception('network down'));

    await pumpToggle(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not save attendance'), findsOneWidget);
  });

  testWidgets('renders nothing when the signed-in teacher has no center',
      (tester) async {
    // AppUser.centerId is nullable; markAttendance requires a non-null
    // center_id, so with none the control must not appear rather than crash.
    await pumpToggle(tester, user: _teacher(centerId: null));
    await tester.pumpAndSettle();

    expect(find.byType(StaffAttendanceToggle), findsOneWidget);
    expect(find.text('Present'), findsNothing);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/profile/widgets/staff_attendance_toggle_test.dart`
Expected: FAIL — cannot resolve `staff_attendance_toggle.dart`.

- [ ] **Step 3: Write the implementation**

Create `lib/features/profile/widgets/staff_attendance_toggle.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/staff_attendance.dart';
import '../../../core/controllers/staff_attendance_controller.dart';
import '../../../shared/widgets/app_loader.dart';

// Lets a teacher mark their own attendance for today, from their Profile
// tab. The only control this schema piece of work ships -- the director-
// facing surface (marking any teacher, seeing every teacher's status) is a
// later plan's job. See
// docs/superpowers/specs/2026-09-02-staff-attendance-schema-design.md.
//
// Renders nothing for a non-teacher, and nothing for a teacher with no
// center_id (AppUser.centerId is nullable; markAttendance requires one).
// ProfileScreen decides whether to show this at all by role; the centerId
// check lives here since it is about this control's own precondition, not
// about who should see it.
class StaffAttendanceToggle extends ConsumerStatefulWidget {
  const StaffAttendanceToggle({super.key});

  @override
  ConsumerState<StaffAttendanceToggle> createState() => _StaffAttendanceToggleState();
}

class _StaffAttendanceToggleState extends ConsumerState<StaffAttendanceToggle> {
  // Captured once, like mark_attendance_screen.dart's _todayDate: a mark
  // made right before midnight must not silently target a different day
  // than what was on screen when the widget built.
  late final DateTime _todayDate = DateTime.now();
  late final String _today = _todayDate.toIso8601String().substring(0, 10);

  late Future<StaffAttendance?> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<StaffAttendance?> _load() async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return null;
    final all = await ref.read(staffAttendanceControllerProvider).fetchForDate(_today);
    // fetchForDate returns every staff member's row for the day -- keep
    // only this user's own.
    for (final record in all) {
      if (record.staffId == user.id) return record;
    }
    return null;
  }

  Future<void> _setStatus(AttendanceStatus status, StaffAttendance? existing) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null || user.centerId == null) return;
    setState(() => _busy = true);
    try {
      final updated = await ref.read(staffAttendanceControllerProvider).markAttendance(
            staffId: user.id,
            centerId: user.centerId!,
            date: _today,
            status: status,
            actorUid: user.id,
            existingId: existing?.id,
          );
      if (mounted) {
        setState(() {
          _future = Future.value(updated);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save attendance: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;
    if (user == null || user.role != 'teacher' || user.centerId == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<StaffAttendance?>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: AppLoader(size: 20)),
          );
        }
        final existing = snapshot.data;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Today's attendance", style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final status in const [AttendanceStatus.present, AttendanceStatus.absent])
                    ChoiceChip(
                      label: Text(status == AttendanceStatus.present ? 'Present' : 'Absent'),
                      selected: existing?.status == status,
                      onSelected: _busy ? null : (_) => _setStatus(status, existing),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/profile/widgets/staff_attendance_toggle_test.dart`
Expected: PASS — 7 tests.

- [ ] **Step 5: Wire it into `ProfileScreen`**

In `lib/features/profile/profile_screen.dart`, add the import:

```dart
import 'widgets/staff_attendance_toggle.dart';
```

Insert the toggle after the Role info tile and before the `Profile details` button — i.e. immediately after this existing block:

```dart
            _InfoTile(
              icon: Icons.badge_outlined,
              label: 'Role',
              value: user.role[0].toUpperCase() + user.role.substring(1),
            ),
```

add:

```dart
            const StaffAttendanceToggle(),
```

so it reads:

```dart
            _InfoTile(
              icon: Icons.badge_outlined,
              label: 'Role',
              value: user.role[0].toUpperCase() + user.role.substring(1),
            ),
            const StaffAttendanceToggle(),
            const SizedBox(height: 24),
```

- [ ] **Step 6: Update `profile_screen_test.dart` so it still passes**

`ProfileScreen`'s test does not currently override `staffAttendanceControllerProvider`, and its default `_user()` helper has `role: 'teacher'` — so every existing test in this file will now try to build a real `StaffAttendanceToggle` against an unmocked controller and fail.

In `test/features/profile/profile_screen_test.dart`:

Add imports:

```dart
import 'package:kids_management/core/models/attendance.dart';
import 'package:kids_management/core/controllers/staff_attendance_controller.dart';
```

Add a mock class:

```dart
class MockStaffAttendanceController extends Mock implements StaffAttendanceController {}
```

Add a fallback registration inside `setUpAll`:

```dart
    registerFallbackValue(AttendanceStatus.present);
```

Add a controller instance and override:

```dart
  late MockStaffAttendanceController mockStaffAttendance;
```

in `setUp`:

```dart
    mockStaffAttendance = MockStaffAttendanceController();
    when(() => mockStaffAttendance.fetchForDate(any())).thenAnswer((_) async => []);
```

in `pumpScreen`'s `overrides` list:

```dart
            staffAttendanceControllerProvider.overrideWithValue(mockStaffAttendance),
```

- [ ] **Step 7: Run this screen's tests**

Run: `flutter test test/features/profile/profile_screen_test.dart`
Expected: PASS, same count as before this task (the toggle is exercised by its own test file; this file only needs to not crash).

- [ ] **Step 8: Run the full suite**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` and `All tests passed!`. Report the actual final count — this plan adds 4 model tests + 7 toggle tests to the 226 baseline; confirm from real output, do not assume the arithmetic.

- [ ] **Step 9: Commit**

```bash
git add lib/features/profile/widgets/staff_attendance_toggle.dart lib/features/profile/profile_screen.dart test/features/profile/widgets/staff_attendance_toggle_test.dart test/features/profile/profile_screen_test.dart
git commit -m "feat: teacher self-marks their own daily attendance from Profile"
```

---

### Task 5: Update the design docs

**Files:**
- Modify: `docs/superpowers/specs/2026-07-01-childcare-management-design.md`

- [ ] **Step 1: Add a schema entry for `staff_attendance`**

Near the existing `attendance` table's schema section, add a short paragraph: `staff_attendance` exists, teacher self-marks / director marks any teacher in their center, no photos, and a pointer to `docs/superpowers/specs/2026-09-02-staff-attendance-schema-design.md` for the full reasoning.

- [ ] **Step 2: Note the deliberate gap**

State plainly, near that entry: directors still cannot mark child attendance — this was considered and explicitly declined. Do not word this as "not yet done"; it reads as a to-do otherwise, and it is a decision, not a gap waiting to be filled.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-07-01-childcare-management-design.md
git commit -m "docs: record the staff_attendance table in the main design spec"
```

---

## Done when

- The user has run the migration SQL and confirmed the teacher self-marking RLS case by hand.
- `flutter analyze` is clean and the full suite passes.
- A signed-in teacher sees a "Today's attendance" Present/Absent control on their Profile tab; tapping it saves and reflects the saved state on next load.
- A signed-in parent or director sees no such control.
- `attendance` (child) table and its RLS are byte-for-byte unchanged from before this plan.
