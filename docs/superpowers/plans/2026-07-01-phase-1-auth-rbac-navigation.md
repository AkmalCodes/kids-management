# Childcare App — Phase 1: Auth, RBAC & Navigation Shell (Supabase)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the foundational Supabase auth + role-based navigation shell that all future feature phases plug into.

**Architecture:** Single Flutter app. Supabase Auth handles email/password login. A `profiles` table in PostgreSQL stores each user's role. After sign-in, the app reads `profiles.role` and renders the correct shell (`ParentShell`, `TeacherShell`, or `DirectorShell`), each with a `BottomNavigationBar` and placeholder tab pages. State is managed with `flutter_riverpod`. RBAC is enforced at two levels: Flutter routing (app) and Row Level Security policies (database).

**Tech Stack:** Flutter ≥3.12.2, Dart ≥3.0.0, supabase_flutter ^2.5.0, flutter_riverpod ^2.5.1, mocktail ^1.0.0 (test)

## Global Constraints

- Flutter SDK: `^3.12.2`
- Package name: `test_flutter` (existing project — used in all import paths)
- All tables include: `created_at`, `updated_at`, `created_by`, `updated_by`
- Roles: `'parent'`, `'teacher'`, `'director'` — set by Director only, never self-assigned
- State management: `flutter_riverpod` 2.x
- Target platforms Phase 1: Android + iOS
- Supabase URL and anon key passed via `--dart-define` at build time, never hardcoded

---

### Task 1: Initialize git + clean project + add dependencies

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/main.dart`
- Modify: `test/widget_test.dart`

- [ ] **Step 1: Initialize git**

```bash
git init
git add .
git commit -m "chore: initial commit — Flutter beginner showcase (pre-childcare)"
```

- [ ] **Step 2: Replace pubspec.yaml dependencies**

Replace the `dependencies` and `dev_dependencies` blocks with:

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  supabase_flutter: ^2.5.0
  flutter_riverpod: ^2.5.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  mocktail: ^1.0.0
```

- [ ] **Step 3: Replace lib/main.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/auth/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
  runApp(const ProviderScope(child: ChildcareApp()));
}

class ChildcareApp extends StatelessWidget {
  const ChildcareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Childcare Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}
```

> `auth_gate.dart` does not exist yet — the app will not compile until Task 5. That is expected.

> **What `String.fromEnvironment` does:** Instead of hardcoding `url: 'https://abc.supabase.co'`, this reads the value from a `--dart-define` flag you pass at run time (e.g. `flutter run --dart-define=SUPABASE_URL=https://...`). Your credentials never touch the source code.

- [ ] **Step 4: Replace test/widget_test.dart**

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Tests added per feature task.
}
```

- [ ] **Step 5: Run flutter pub get**

```bash
flutter pub get
```

Expected: packages download, no version conflicts.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/main.dart test/widget_test.dart
git commit -m "chore: add Supabase + Riverpod deps, replace main.dart with app bootstrap"
```

---

### Task 2: Supabase project setup + database schema

> This task requires manual steps in a browser. It cannot be automated.

**Files created:** None in Flutter — this task lives entirely in Supabase dashboard.

- [ ] **Step 1: Create a Supabase project**

Go to https://supabase.com → **New project** → name it `childcare-manager` → set a strong database password → choose nearest region → **Create project**.

Wait ~2 minutes for provisioning.

- [ ] **Step 2: Get your project credentials**

In your Supabase project → **Settings → API**. Note down:
- **Project URL** (looks like `https://xxxx.supabase.co`)
- **anon / public key** (long JWT string)

You will pass these as `--dart-define` flags when running the app (never paste them into code).

- [ ] **Step 3: Enable Email Auth**

**Authentication → Providers → Email** — make sure it is enabled (it is by default). Disable "Confirm email" for now so you can test without email verification.

- [ ] **Step 4: Run the database schema**

Go to **SQL Editor** in your Supabase project → **New query** → paste and run the following SQL in order:

```sql
-- 1. centers (created first — other tables reference it)
CREATE TABLE centers (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name       TEXT NOT NULL,
  address    TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  created_by UUID REFERENCES auth.users(id),
  updated_by UUID REFERENCES auth.users(id)
);

-- 2. profiles (one row per auth user)
CREATE TABLE profiles (
  id         UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  role       TEXT NOT NULL CHECK (role IN ('parent', 'teacher', 'director')),
  name       TEXT NOT NULL,
  phone      TEXT DEFAULT '',
  center_id  UUID REFERENCES centers(id),
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  created_by UUID REFERENCES auth.users(id),
  updated_by UUID REFERENCES auth.users(id)
);

-- 3. children
CREATE TABLE children (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name        TEXT NOT NULL,
  dob         DATE NOT NULL,
  center_id   UUID REFERENCES centers(id) NOT NULL,
  room_id     TEXT DEFAULT '',
  teacher_id  UUID REFERENCES auth.users(id),
  allergies   TEXT DEFAULT '',
  notes       TEXT DEFAULT '',
  enrolled_at DATE DEFAULT CURRENT_DATE NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  created_by  UUID REFERENCES auth.users(id),
  updated_by  UUID REFERENCES auth.users(id)
);

-- 4. children_parents junction
CREATE TABLE children_parents (
  child_id  UUID REFERENCES children(id) ON DELETE CASCADE,
  parent_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  PRIMARY KEY (child_id, parent_id)
);

-- 5. schedules
CREATE TABLE schedules (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  type       TEXT NOT NULL CHECK (type IN ('child', 'teacher')),
  ref_id     UUID NOT NULL,
  center_id  UUID REFERENCES centers(id) NOT NULL,
  entries    JSONB DEFAULT '[]' NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  created_by UUID REFERENCES auth.users(id),
  updated_by UUID REFERENCES auth.users(id)
);

-- 6. attendance
CREATE TABLE attendance (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  child_id   UUID REFERENCES children(id) NOT NULL,
  center_id  UUID REFERENCES centers(id) NOT NULL,
  date       DATE NOT NULL,
  status     TEXT NOT NULL CHECK (status IN ('present', 'absent', 'late', 'excused')),
  notes      TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  created_by UUID REFERENCES auth.users(id),
  updated_by UUID REFERENCES auth.users(id),
  UNIQUE (child_id, date)
);

-- 7. lesson_plans
CREATE TABLE lesson_plans (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  teacher_id UUID REFERENCES auth.users(id) NOT NULL,
  center_id  UUID REFERENCES centers(id) NOT NULL,
  title      TEXT NOT NULL,
  date       DATE NOT NULL,
  content    TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  created_by UUID REFERENCES auth.users(id),
  updated_by UUID REFERENCES auth.users(id)
);

-- 8. daily_reports
CREATE TABLE daily_reports (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  child_id   UUID REFERENCES children(id) NOT NULL,
  teacher_id UUID REFERENCES auth.users(id) NOT NULL,
  center_id  UUID REFERENCES centers(id) NOT NULL,
  date       DATE NOT NULL,
  text       TEXT DEFAULT '',
  image_urls JSONB DEFAULT '[]' NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  created_by UUID REFERENCES auth.users(id),
  updated_by UUID REFERENCES auth.users(id),
  UNIQUE (child_id, date)
);
```

- [ ] **Step 5: Enable Row Level Security + add policies**

In the same SQL Editor, run:

```sql
-- Enable RLS
ALTER TABLE profiles      ENABLE ROW LEVEL SECURITY;
ALTER TABLE children      ENABLE ROW LEVEL SECURITY;
ALTER TABLE children_parents ENABLE ROW LEVEL SECURITY;
ALTER TABLE schedules     ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance    ENABLE ROW LEVEL SECURITY;
ALTER TABLE lesson_plans  ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_reports ENABLE ROW LEVEL SECURITY;

-- Helper function: get current user's role
CREATE OR REPLACE FUNCTION current_role_name()
RETURNS TEXT AS $$
  SELECT role FROM profiles WHERE id = auth.uid();
$$ LANGUAGE sql STABLE SECURITY DEFINER;  

-- profiles: read own row, or read all if director
CREATE POLICY "profiles_select" ON profiles FOR SELECT
  USING (id = auth.uid() OR current_role_name() = 'director');
CREATE POLICY "profiles_insert" ON profiles FOR INSERT
  WITH CHECK (current_role_name() = 'director' OR id = auth.uid());
CREATE POLICY "profiles_update" ON profiles FOR UPDATE
  USING (id = auth.uid() OR current_role_name() = 'director');

-- children: teachers see their class; parents see their linked child; directors see all
CREATE POLICY "children_select" ON children FOR SELECT
  USING (
    current_role_name() = 'director'
    OR teacher_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM children_parents
      WHERE child_id = children.id AND parent_id = auth.uid()
    )
  );
CREATE POLICY "children_insert" ON children FOR INSERT
  WITH CHECK (current_role_name() = 'director');
CREATE POLICY "children_update" ON children FOR UPDATE
  USING (current_role_name() = 'director');

-- children_parents
CREATE POLICY "children_parents_select" ON children_parents FOR SELECT
  USING (parent_id = auth.uid() OR current_role_name() = 'director');
CREATE POLICY "children_parents_insert" ON children_parents FOR INSERT
  WITH CHECK (current_role_name() = 'director');

-- schedules: director manages both child and teacher schedules; teachers
-- read their own, parents read their linked children's
CREATE POLICY "schedules_select" ON schedules FOR SELECT
  USING (
    current_role_name() = 'director'
    OR (type = 'teacher' AND ref_id = auth.uid())
    OR (type = 'child' AND EXISTS (
      SELECT 1 FROM children_parents
      WHERE child_id = schedules.ref_id AND parent_id = auth.uid()
    ))
  );
CREATE POLICY "schedules_insert" ON schedules FOR INSERT
  WITH CHECK (current_role_name() = 'director');
CREATE POLICY "schedules_update" ON schedules FOR UPDATE
  USING (current_role_name() = 'director');

-- attendance: teachers insert/update for their class; parents read their child's; directors read all
CREATE POLICY "attendance_select" ON attendance FOR SELECT
  USING (
    current_role_name() = 'director'
    OR created_by = auth.uid()
    OR EXISTS (
      SELECT 1 FROM children_parents
      WHERE child_id = attendance.child_id AND parent_id = auth.uid()
    )
  );
CREATE POLICY "attendance_insert" ON attendance FOR INSERT
  WITH CHECK (current_role_name() = 'teacher');
CREATE POLICY "attendance_update" ON attendance FOR UPDATE
  USING (current_role_name() = 'teacher' AND created_by = auth.uid());

-- lesson_plans: teachers manage their own; directors read all
CREATE POLICY "lesson_plans_select" ON lesson_plans FOR SELECT
  USING (teacher_id = auth.uid() OR current_role_name() = 'director');
CREATE POLICY "lesson_plans_insert" ON lesson_plans FOR INSERT
  WITH CHECK (current_role_name() = 'teacher');
CREATE POLICY "lesson_plans_update" ON lesson_plans FOR UPDATE
  USING (current_role_name() = 'teacher' AND teacher_id = auth.uid());

-- daily_reports: teachers write; parents read their child's; directors read all
CREATE POLICY "daily_reports_select" ON daily_reports FOR SELECT
  USING (
    teacher_id = auth.uid()
    OR current_role_name() = 'director'
    OR EXISTS (
      SELECT 1 FROM children_parents
      WHERE child_id = daily_reports.child_id AND parent_id = auth.uid()
    )
  );
CREATE POLICY "daily_reports_insert" ON daily_reports FOR INSERT
  WITH CHECK (current_role_name() = 'teacher');
CREATE POLICY "daily_reports_update" ON daily_reports FOR UPDATE
  USING (current_role_name() = 'teacher' AND teacher_id = auth.uid());
```

- [ ] **Step 6: Verify tables exist**

In Supabase → **Table Editor** — you should see: `centers`, `profiles`, `children`, `children_parents`, `schedules`, `attendance`, `lesson_plans`, `daily_reports`.

- [ ] **Step 7: Create first Director account manually**

In Supabase → **Authentication → Users** → **Add user** → enter an email and password for the Director.

Then in **SQL Editor** run (replace the UUID with the one shown for the new user):

```sql
INSERT INTO profiles (id, role, name, phone, center_id, created_by, updated_by)
VALUES (
  '<paste-director-user-id-here>',
  'director',
  'Center Director',
  '',
  NULL,
  '<paste-director-user-id-here>',
  '<paste-director-user-id-here>'
);
```

- [ ] **Step 8: No git commit needed** — this task was all in the Supabase dashboard.

---

### Task 3: Core data models

**Files:**
- Create: `lib/core/models/app_user.dart`
- Create: `lib/core/models/child.dart`
- Create: `lib/core/models/schedule.dart`
- Create: `lib/core/models/attendance.dart`
- Create: `lib/core/models/lesson_plan.dart`
- Create: `lib/core/models/daily_report.dart`
- Create: `test/core/models/app_user_test.dart`

**Interfaces:**
- Produces:
  - `AppUser.fromJson(Map<String, dynamic>)` → `AppUser`
  - `AppUser.toJson()` → `Map<String, dynamic>`
  - Same `fromJson`/`toJson` pattern for `Child`, `Schedule`, `Attendance`, `LessonPlan`, `DailyReport`
  - `ScheduleEntry.fromJson(Map)` / `.toJson()`
  - `AttendanceStatus` enum: `present`, `absent`, `late`, `excused`

> **Why `fromJson` instead of `fromFirestore`:** Supabase returns plain Dart `Map<String, dynamic>` from its queries — exactly like PHP's `json_decode()` returns an associative array. No special wrapper needed.

- [ ] **Step 1: Write failing test for AppUser**

Create `test/core/models/app_user_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:test_flutter/core/models/app_user.dart';

void main() {
  group('AppUser', () {
    final sampleJson = {
      'id': 'uid-1',
      'role': 'teacher',
      'name': 'Alice',
      'phone': '0123456789',
      'center_id': 'center-1',
      'created_at': '2026-07-01T00:00:00.000Z',
      'updated_at': '2026-07-01T00:00:00.000Z',
      'created_by': 'director-1',
      'updated_by': 'director-1',
    };

    test('fromJson parses all fields', () {
      final user = AppUser.fromJson(sampleJson);

      expect(user.id, 'uid-1');
      expect(user.role, 'teacher');
      expect(user.name, 'Alice');
      expect(user.phone, '0123456789');
      expect(user.centerId, 'center-1');
      expect(user.createdBy, 'director-1');
      expect(user.updatedBy, 'director-1');
    });

    test('toJson serializes all fields except id', () {
      final user = AppUser.fromJson(sampleJson);
      final json = user.toJson();

      expect(json['role'], 'teacher');
      expect(json['name'], 'Alice');
      expect(json['created_by'], 'director-1');
      expect(json.containsKey('id'), isFalse); // id is the PK, not sent in body
    });

    test('fromJson handles null phone gracefully', () {
      final json = Map<String, dynamic>.from(sampleJson);
      json['phone'] = null;
      final user = AppUser.fromJson(json);
      expect(user.phone, '');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/core/models/app_user_test.dart
```

Expected: FAIL — `app_user.dart` not found.

- [ ] **Step 3: Create lib/core/models/app_user.dart**

```dart
class AppUser {
  final String id;
  final String role;
  final String name;
  final String phone;
  final String? centerId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const AppUser({
    required this.id,
    required this.role,
    required this.name,
    required this.phone,
    required this.centerId,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    role: json['role'] as String,
    name: json['name'] as String,
    phone: json['phone'] as String? ?? '',
    centerId: json['center_id'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    createdBy: json['created_by'] as String?,
    updatedBy: json['updated_by'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'role': role,
    'name': name,
    'phone': phone,
    'center_id': centerId,
    'created_by': createdBy,
    'updated_by': updatedBy,
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/core/models/app_user_test.dart
```

Expected: 3 tests PASS

- [ ] **Step 5: Create lib/core/models/child.dart**

```dart
class Child {
  final String id;
  final String name;
  final DateTime dob;
  final String centerId;
  final String roomId;
  final String? teacherId;
  final String allergies;
  final String notes;
  final DateTime enrolledAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const Child({
    required this.id,
    required this.name,
    required this.dob,
    required this.centerId,
    required this.roomId,
    required this.teacherId,
    required this.allergies,
    required this.notes,
    required this.enrolledAt,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
  });

  factory Child.fromJson(Map<String, dynamic> json) => Child(
    id: json['id'] as String,
    name: json['name'] as String,
    dob: DateTime.parse(json['dob'] as String),
    centerId: json['center_id'] as String,
    roomId: json['room_id'] as String? ?? '',
    teacherId: json['teacher_id'] as String?,
    allergies: json['allergies'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
    enrolledAt: DateTime.parse(json['enrolled_at'] as String),
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    createdBy: json['created_by'] as String?,
    updatedBy: json['updated_by'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'dob': dob.toIso8601String().substring(0, 10), // YYYY-MM-DD
    'center_id': centerId,
    'room_id': roomId,
    'teacher_id': teacherId,
    'allergies': allergies,
    'notes': notes,
    'enrolled_at': enrolledAt.toIso8601String().substring(0, 10),
    'created_by': createdBy,
    'updated_by': updatedBy,
  };
}
```

- [ ] **Step 6: Create lib/core/models/schedule.dart**

```dart
class ScheduleEntry {
  final String day;
  final String startTime;
  final String endTime;
  final String label;

  const ScheduleEntry({
    required this.day,
    required this.startTime,
    required this.endTime,
    required this.label,
  });

  factory ScheduleEntry.fromJson(Map<String, dynamic> json) => ScheduleEntry(
    day: json['day'] as String,
    startTime: json['start_time'] as String,
    endTime: json['end_time'] as String,
    label: json['label'] as String,
  );

  Map<String, dynamic> toJson() => {
    'day': day,
    'start_time': startTime,
    'end_time': endTime,
    'label': label,
  };
}

class Schedule {
  final String id;
  final String type; // 'child' | 'teacher'
  final String refId;
  final String centerId;
  final List<ScheduleEntry> entries;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const Schedule({
    required this.id,
    required this.type,
    required this.refId,
    required this.centerId,
    required this.entries,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
  });

  factory Schedule.fromJson(Map<String, dynamic> json) => Schedule(
    id: json['id'] as String,
    type: json['type'] as String,
    refId: json['ref_id'] as String,
    centerId: json['center_id'] as String,
    entries: (json['entries'] as List)
        .map((e) => ScheduleEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    createdBy: json['created_by'] as String?,
    updatedBy: json['updated_by'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'ref_id': refId,
    'center_id': centerId,
    'entries': entries.map((e) => e.toJson()).toList(),
    'created_by': createdBy,
    'updated_by': updatedBy,
  };
}
```

- [ ] **Step 7: Create lib/core/models/attendance.dart**

```dart
enum AttendanceStatus { present, absent, late, excused }

class Attendance {
  final String id;
  final String childId;
  final String centerId;
  final String date; // YYYY-MM-DD
  final AttendanceStatus status;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const Attendance({
    required this.id,
    required this.childId,
    required this.centerId,
    required this.date,
    required this.status,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
  });

  factory Attendance.fromJson(Map<String, dynamic> json) => Attendance(
    id: json['id'] as String,
    childId: json['child_id'] as String,
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
    'child_id': childId,
    'center_id': centerId,
    'date': date,
    'status': status.name,
    'notes': notes,
    'created_by': createdBy,
    'updated_by': updatedBy,
  };
}
```

- [ ] **Step 8: Create lib/core/models/lesson_plan.dart**

```dart
class LessonPlan {
  final String id;
  final String teacherId;
  final String centerId;
  final String title;
  final String date; // YYYY-MM-DD
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const LessonPlan({
    required this.id,
    required this.teacherId,
    required this.centerId,
    required this.title,
    required this.date,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
  });

  factory LessonPlan.fromJson(Map<String, dynamic> json) => LessonPlan(
    id: json['id'] as String,
    teacherId: json['teacher_id'] as String,
    centerId: json['center_id'] as String,
    title: json['title'] as String,
    date: json['date'] as String,
    content: json['content'] as String? ?? '',
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    createdBy: json['created_by'] as String?,
    updatedBy: json['updated_by'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'teacher_id': teacherId,
    'center_id': centerId,
    'title': title,
    'date': date,
    'content': content,
    'created_by': createdBy,
    'updated_by': updatedBy,
  };
}
```

- [ ] **Step 9: Create lib/core/models/daily_report.dart**

```dart
class DailyReport {
  final String id;
  final String childId;
  final String teacherId;
  final String centerId;
  final String date; // YYYY-MM-DD
  final String text;
  final List<String> imageUrls;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const DailyReport({
    required this.id,
    required this.childId,
    required this.teacherId,
    required this.centerId,
    required this.date,
    required this.text,
    required this.imageUrls,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
  });

  factory DailyReport.fromJson(Map<String, dynamic> json) => DailyReport(
    id: json['id'] as String,
    childId: json['child_id'] as String,
    teacherId: json['teacher_id'] as String,
    centerId: json['center_id'] as String,
    date: json['date'] as String,
    text: json['text'] as String? ?? '',
    imageUrls: List<String>.from(json['image_urls'] as List),
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    createdBy: json['created_by'] as String?,
    updatedBy: json['updated_by'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'child_id': childId,
    'teacher_id': teacherId,
    'center_id': centerId,
    'date': date,
    'text': text,
    'image_urls': imageUrls,
    'created_by': createdBy,
    'updated_by': updatedBy,
  };
}
```

- [ ] **Step 10: Run all model tests**

```bash
flutter test test/core/models/
```

Expected: 3 tests PASS (AppUser has tests; others verified when services use them in later tasks).

- [ ] **Step 11: Commit**

```bash
git add lib/core/models/ test/core/models/
git commit -m "feat: add all data models with fromJson/toJson"
```

---

### Task 4: AuthService + Riverpod providers

**Files:**
- Create: `lib/core/auth/auth_service.dart`
- Create: `test/core/auth/auth_service_test.dart`

**Interfaces:**
- Consumes: `AppUser` from `lib/core/models/app_user.dart`
- Produces:
  - `supabaseClientProvider` → `Provider<SupabaseClient>`
  - `authServiceProvider` → `Provider<AuthService>`
  - `currentUserProvider` → `StreamProvider<AppUser?>`
  - `AuthService.signIn(String email, String password)` → `Future<void>`
  - `AuthService.signOut()` → `Future<void>`

- [ ] **Step 1: Write failing test**

Create `test/core/auth/auth_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test_flutter/core/auth/auth_service.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}
class MockSupabaseClient extends Mock implements SupabaseClient {}

void main() {
  late MockGoTrueClient mockAuth;
  late MockSupabaseClient mockClient;
  late AuthService service;

  setUp(() {
    mockAuth = MockGoTrueClient();
    mockClient = MockSupabaseClient();
    when(() => mockClient.auth).thenReturn(mockAuth);
    service = AuthService(client: mockClient);
  });

  group('AuthService', () {
    test('signIn calls signInWithPassword', () async {
      when(() => mockAuth.signInWithPassword(
        email: any(named: 'email'),
        password: any(named: 'password'),
      )).thenAnswer((_) async => AuthResponse());

      await service.signIn('test@test.com', 'password123');

      verify(() => mockAuth.signInWithPassword(
        email: 'test@test.com',
        password: 'password123',
      )).called(1);
    });

    test('signOut calls supabase auth signOut', () async {
      when(() => mockAuth.signOut()).thenAnswer((_) async {});

      await service.signOut();

      verify(() => mockAuth.signOut()).called(1);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/core/auth/auth_service_test.dart
```

Expected: FAIL — `auth_service.dart` not found.

- [ ] **Step 3: Create lib/core/auth/auth_service.dart**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';

class AuthService {
  final SupabaseClient _client;

  AuthService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  Stream<AppUser?> get userStream =>
      _client.auth.onAuthStateChange.asyncMap((event) async {
        final session = event.session;
        if (session == null) return null;
        final data = await _client
            .from('profiles')
            .select()
            .eq('id', session.user.id)
            .single();
        return AppUser.fromJson(data);
      });

  Future<void> signIn(String email, String password) =>
      _client.auth.signInWithPassword(email: email, password: password);

  Future<void> signOut() => _client.auth.signOut();
}

final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(client: ref.watch(supabaseClientProvider)),
);

final currentUserProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authServiceProvider).userStream;
});
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/core/auth/auth_service_test.dart
```

Expected: 2 tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/core/auth/auth_service.dart test/core/auth/auth_service_test.dart
git commit -m "feat: add AuthService with Supabase and Riverpod providers"
```

---

### Task 5: LoginScreen

**Files:**
- Create: `lib/features/auth/login_screen.dart`
- Create: `test/features/auth/login_screen_test.dart`

**Interfaces:**
- Consumes: `authServiceProvider` from `lib/core/auth/auth_service.dart`
- Produces: `LoginScreen` widget — shown by `AuthGate` when no session exists

- [ ] **Step 1: Write failing widget test**

Create `test/features/auth/login_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_flutter/features/auth/login_screen.dart';

void main() {
  testWidgets('LoginScreen shows two fields and a Sign In button', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('shows email error when Sign In tapped with empty fields', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );
    await tester.tap(find.text('Sign In'));
    await tester.pump();
    expect(find.text('Please enter your email'), findsOneWidget);
  });

  testWidgets('shows password error when only email filled', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );
    await tester.enterText(find.byType(TextFormField).first, 'test@test.com');
    await tester.tap(find.text('Sign In'));
    await tester.pump();
    expect(find.text('Please enter your password'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/features/auth/login_screen_test.dart
```

Expected: FAIL — `login_screen.dart` not found.

- [ ] **Step 3: Create lib/features/auth/login_screen.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authServiceProvider).signIn(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
    } catch (_) {
      setState(() => _error = 'Invalid email or password. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.child_care, size: 72, color: Colors.blue),
                const SizedBox(height: 16),
                const Text(
                  'Childcare Manager',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Please enter your email' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Please enter your password' : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _signIn,
                    child: _loading
                        ? const SizedBox(
                            height: 20, width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sign In'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/features/auth/login_screen_test.dart
```

Expected: 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/auth/login_screen.dart test/features/auth/login_screen_test.dart
git commit -m "feat: add LoginScreen with form validation"
```

---

### Task 6: AuthGate + RoleRouter + role shell stubs

**Files:**
- Create: `lib/features/parent/parent_shell.dart`
- Create: `lib/features/teacher/teacher_shell.dart`
- Create: `lib/features/director/director_shell.dart`
- Create: `lib/core/auth/role_router.dart`
- Create: `lib/core/auth/auth_gate.dart`
- Create: `test/core/auth/role_router_test.dart`

**Interfaces:**
- Consumes: `currentUserProvider` from `lib/core/auth/auth_service.dart`
- Consumes: `AppUser` from `lib/core/models/app_user.dart`
- Produces: `AuthGate` (referenced in `main.dart`), `RoleRouter`

- [ ] **Step 1: Create lib/features/parent/parent_shell.dart**

```dart
import 'package:flutter/material.dart';

class ParentShell extends StatelessWidget {
  const ParentShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Parent')));
  }
}
```

- [ ] **Step 2: Create lib/features/teacher/teacher_shell.dart**

```dart
import 'package:flutter/material.dart';

class TeacherShell extends StatelessWidget {
  const TeacherShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Teacher')));
  }
}
```

- [ ] **Step 3: Create lib/features/director/director_shell.dart**

```dart
import 'package:flutter/material.dart';

class DirectorShell extends StatelessWidget {
  const DirectorShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Director')));
  }
}
```

- [ ] **Step 4: Write failing test for RoleRouter**

Create `test/core/auth/role_router_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_flutter/core/auth/auth_service.dart';
import 'package:test_flutter/core/auth/role_router.dart';
import 'package:test_flutter/core/models/app_user.dart';

AppUser _user(String role) => AppUser(
  id: 'uid-1',
  role: role,
  name: 'Test',
  phone: '',
  centerId: 'c-1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'd-1',
  updatedBy: 'd-1',
);

void main() {
  testWidgets('routes parent to ParentShell', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_user('parent'))),
      ],
      child: const MaterialApp(home: RoleRouter()),
    ));
    await tester.pump();
    expect(find.text('Parent'), findsOneWidget);
  });

  testWidgets('routes teacher to TeacherShell', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_user('teacher'))),
      ],
      child: const MaterialApp(home: RoleRouter()),
    ));
    await tester.pump();
    expect(find.text('Teacher'), findsOneWidget);
  });

  testWidgets('routes director to DirectorShell', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_user('director'))),
      ],
      child: const MaterialApp(home: RoleRouter()),
    ));
    await tester.pump();
    expect(find.text('Director'), findsOneWidget);
  });
}
```

- [ ] **Step 5: Run test to verify it fails**

```bash
flutter test test/core/auth/role_router_test.dart
```

Expected: FAIL — `role_router.dart` not found.

- [ ] **Step 6: Create lib/core/auth/role_router.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_service.dart';
import '../../features/parent/parent_shell.dart';
import '../../features/teacher/teacher_shell.dart';
import '../../features/director/director_shell.dart';

class RoleRouter extends ConsumerWidget {
  const RoleRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    return userAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(child: Text('Error loading profile: $e')),
      ),
      data: (user) {
        if (user == null) {
          return const Scaffold(
            body: Center(
              child: Text('Account not found. Contact your administrator.'),
            ),
          );
        }
        return switch (user.role) {
          'parent'   => const ParentShell(),
          'teacher'  => const TeacherShell(),
          'director' => const DirectorShell(),
          final role => Scaffold(
              body: Center(child: Text('Unknown role: $role')),
            ),
        };
      },
    );
  }
}
```

- [ ] **Step 7: Create lib/core/auth/auth_gate.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_service.dart';
import '../auth/role_router.dart';
import '../../features/auth/login_screen.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    return userAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const LoginScreen(),
      data: (user) => user == null ? const LoginScreen() : const RoleRouter(),
    );
  }
}
```

- [ ] **Step 8: Run RoleRouter test**

```bash
flutter test test/core/auth/role_router_test.dart
```

Expected: 3 tests PASS

- [ ] **Step 9: Run all tests**

```bash
flutter test
```

Expected: all PASS

- [ ] **Step 10: Commit**

```bash
git add lib/core/auth/ lib/features/parent/ lib/features/teacher/ lib/features/director/ test/core/auth/
git commit -m "feat: add AuthGate, RoleRouter and role shell stubs"
```

---

### Task 7: Bottom navigation for each shell

**Files:**
- Modify: `lib/features/parent/parent_shell.dart`
- Modify: `lib/features/teacher/teacher_shell.dart`
- Modify: `lib/features/director/director_shell.dart`
- Modify: `test/core/auth/role_router_test.dart`
- Create: `test/features/parent/parent_shell_test.dart`
- Create: `test/features/teacher/teacher_shell_test.dart`
- Create: `test/features/director/director_shell_test.dart`

**Interfaces:**
- Produces: Each shell renders a `BottomNavigationBar` with correct tabs; tapping switches the body content.

> **Note:** Updating the shells removes the plain `Text('Parent')` etc. that `role_router_test.dart` currently asserts. Update those assertions in Step 8 of this task.

- [ ] **Step 1: Write failing test for ParentShell**

Create `test/features/parent/parent_shell_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_flutter/features/parent/parent_shell.dart';

void main() {
  testWidgets('ParentShell renders Schedule, Attendance and Reports tabs', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ParentShell())),
    );
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Attendance'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
  });

  testWidgets('tapping Attendance tab switches body', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ParentShell())),
    );
    await tester.tap(find.text('Attendance'));
    await tester.pump();
    expect(find.text('Attendance — coming soon'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/features/parent/parent_shell_test.dart
```

Expected: FAIL

- [ ] **Step 3: Replace lib/features/parent/parent_shell.dart**

```dart
import 'package:flutter/material.dart';

class ParentShell extends StatefulWidget {
  const ParentShell({super.key});

  @override
  State<ParentShell> createState() => _ParentShellState();
}

class _ParentShellState extends State<ParentShell> {
  int _index = 0;

  static const _pages = [
    Center(child: Text('Schedule — coming soon')),
    Center(child: Text('Attendance — coming soon')),
    Center(child: Text('Reports — coming soon')),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Childcare Manager'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: _pages[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Schedule',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.check_circle_outline),
            label: 'Attendance',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.article_outlined),
            label: 'Reports',
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Write failing test for TeacherShell**

Create `test/features/teacher/teacher_shell_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_flutter/features/teacher/teacher_shell.dart';

void main() {
  testWidgets('TeacherShell renders four tabs', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: TeacherShell())),
    );
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Attendance'), findsOneWidget);
    expect(find.text('Lesson Plans'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
  });
}
```

- [ ] **Step 5: Replace lib/features/teacher/teacher_shell.dart**

```dart
import 'package:flutter/material.dart';

class TeacherShell extends StatefulWidget {
  const TeacherShell({super.key});

  @override
  State<TeacherShell> createState() => _TeacherShellState();
}

class _TeacherShellState extends State<TeacherShell> {
  int _index = 0;

  static const _pages = [
    Center(child: Text('Schedule — coming soon')),
    Center(child: Text('Attendance — coming soon')),
    Center(child: Text('Lesson Plans — coming soon')),
    Center(child: Text('Reports — coming soon')),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Childcare Manager'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: _pages[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Schedule',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.check_circle_outline),
            label: 'Attendance',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu_book_outlined),
            label: 'Lesson Plans',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.article_outlined),
            label: 'Reports',
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: Write failing test for DirectorShell**

Create `test/features/director/director_shell_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_flutter/features/director/director_shell.dart';

void main() {
  testWidgets('DirectorShell renders four tabs', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: DirectorShell())),
    );
    expect(find.text('Teachers'), findsOneWidget);
    expect(find.text('Schedules'), findsOneWidget);
    expect(find.text('Lesson Plans'), findsOneWidget);
    expect(find.text('Attendance'), findsOneWidget);
  });
}
```

- [ ] **Step 7: Replace lib/features/director/director_shell.dart**

```dart
import 'package:flutter/material.dart';

class DirectorShell extends StatefulWidget {
  const DirectorShell({super.key});

  @override
  State<DirectorShell> createState() => _DirectorShellState();
}

class _DirectorShellState extends State<DirectorShell> {
  int _index = 0;

  static const _pages = [
    Center(child: Text('Teachers — coming soon')),
    Center(child: Text('Schedules — coming soon')),
    Center(child: Text('Lesson Plans — coming soon')),
    Center(child: Text('Attendance — coming soon')),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Childcare Manager'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: _pages[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            label: 'Teachers',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Schedules',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu_book_outlined),
            label: 'Lesson Plans',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.check_circle_outline),
            label: 'Attendance',
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 8: Update role_router_test.dart to match new shell content**

The shells no longer show plain `Text('Parent')` etc. Update the three `expect` lines in `test/core/auth/role_router_test.dart`:

```dart
// parent test
expect(find.text('Schedule — coming soon'), findsOneWidget);

// teacher test
expect(find.text('Schedule — coming soon'), findsOneWidget);

// director test
expect(find.text('Teachers — coming soon'), findsOneWidget);
```

- [ ] **Step 9: Run all tests**

```bash
flutter test
```

Expected: all PASS

- [ ] **Step 10: Commit**

```bash
git add lib/features/ test/features/ test/core/auth/role_router_test.dart
git commit -m "feat: add bottom navigation tabs to all role shells"
```

---

## Phase 1 Complete

At the end of Task 7 the app:
- Boots and initializes Supabase with credentials passed via `--dart-define`
- Shows a validated login screen (email + password)
- Signs in via Supabase Auth, reads `profiles.role` from PostgreSQL
- Routes to the correct shell (Parent / Teacher / Director) based on role
- Shows the correct bottom navigation tabs per role
- RBAC enforced at both app level (routing) and DB level (RLS policies)
- All behavior covered by passing unit and widget tests

**To run the app locally:**
```bash
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

**Next plan:** Phase 2 — Schedules + Attendance (teachers mark attendance, parents and teachers view schedules).
