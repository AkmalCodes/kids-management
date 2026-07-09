# Childcare Management App — Design Spec
**Date:** 2026-07-01
**Status:** Draft — Pending User Approval

---

## 1. Overview

A cross-platform Flutter application for managing a small-to-medium childcare center (1–3 branches, up to 150 children, up to 30 teachers). The app serves three distinct user roles — Parent, Teacher, and Director/Admin — each with a tailored view enforced via Role-Based Access Control (RBAC).

**Priority order for delivery:**
1. Mobile (Android + iOS)
2. Web
3. Tablet

---

## 2. Tech Stack

| Layer | Technology | Reason |
|---|---|---|
| Frontend | Flutter (Dart) | Single codebase for mobile, web, tablet |
| Auth | Supabase Auth | Built-in email/password login, integrates with DB |
| Database | Supabase (PostgreSQL) | SQL — familiar to anyone who knows MySQL |
| File Storage | Supabase Storage | Daily report images, same project as DB |
| Push Notifications | OneSignal (Phase 2+) | Supabase does not include FCM; added later |
| Hosting (web) | Supabase + any static host | DB and auth already on Supabase |

> **Why Supabase over Firebase:** Supabase uses real PostgreSQL. If you know MySQL, you already know ~90% of it — same `SELECT`, `INSERT`, `JOIN`, `WHERE` syntax. Supabase also enforces RBAC at the database level via **Row Level Security (RLS)** policies, which are written in SQL.

---

## 3. Roles & Permissions (RBAC)

Roles are stored in the `profiles` table in Supabase (`profiles.role`). After login, the app reads this field and routes the user to their role-specific shell. RBAC is enforced at two levels: the Flutter app (routing) and the Supabase database (Row Level Security policies — the DB rejects unauthorized queries even if the app is bypassed).

| Feature | Parent | Teacher | Director / Admin |
|---|---|---|---|
| View own child's schedule | ✅ | — | — |
| View own child's attendance | ✅ | — | — |
| View daily reports for own child | ✅ | — | — |
| View own schedule | — | ✅ | — |
| Create / edit lesson plans | — | ✅ | — |
| Create daily reports (text + images) | — | ✅ | — |
| Mark attendance | — | ✅ | — |
| View all teacher schedules | — | — | ✅ |
| View all lesson plans | — | — | ✅ |
| View all attendance records | — | — | ✅ |
| Manage teachers (add / edit / remove) | — | — | ✅ |
| Manage children (enrollment, room assignment) | — | — | ✅ |
| Manage parent accounts | — | — | ✅ |
| Manage center settings | — | — | ✅ |

> **Note:** Director and Admin are the same role for now. Further permission granularity can be added in a future iteration.

---

## 4. Database Schema (PostgreSQL via Supabase)

All tables follow PostgreSQL conventions: `snake_case` column names, `UUID` primary keys, `TIMESTAMPTZ` for timestamps. All tables include the four audit columns: `created_at`, `updated_at`, `created_by`, `updated_by`.

> **MySQL vs PostgreSQL:** The SQL below is standard SQL. If you know MySQL, the only differences you'll notice are: `UUID` instead of `INT AUTO_INCREMENT` for IDs, `TIMESTAMPTZ` instead of `DATETIME`, and `JSONB` instead of `JSON` (PostgreSQL's binary JSON — faster for querying).

### `centers`
```sql
CREATE TABLE centers (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name        TEXT NOT NULL,
  address     TEXT DEFAULT '',
  created_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  created_by  UUID REFERENCES auth.users(id),
  updated_by  UUID REFERENCES auth.users(id)
);
```

### `profiles` (extends Supabase's built-in `auth.users`)
```sql
CREATE TABLE profiles (
  id          UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  role        TEXT NOT NULL CHECK (role IN ('parent', 'teacher', 'director')),
  name        TEXT NOT NULL,
  phone       TEXT DEFAULT '',
  center_id   UUID REFERENCES centers(id),
  created_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  created_by  UUID REFERENCES auth.users(id),
  updated_by  UUID REFERENCES auth.users(id)
);
```
> Supabase Auth manages the email + password in `auth.users`. `profiles` holds everything else. The `id` in `profiles` is the same UUID as in `auth.users`.

### `children`
```sql
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
```

### `children_parents` (junction — one child can have up to 2 parents)
```sql
CREATE TABLE children_parents (
  child_id   UUID REFERENCES children(id) ON DELETE CASCADE,
  parent_id  UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  PRIMARY KEY (child_id, parent_id)
);
```

### `schedules`
```sql
CREATE TABLE schedules (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  type       TEXT NOT NULL CHECK (type IN ('child', 'teacher')),
  ref_id     UUID NOT NULL,  -- child id or teacher user id
  center_id  UUID REFERENCES centers(id) NOT NULL,
  entries    JSONB DEFAULT '[]' NOT NULL,
  -- entries shape: [{ "day": "Monday", "start_time": "08:00", "end_time": "09:00", "label": "Art" }]
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  created_by UUID REFERENCES auth.users(id),
  updated_by UUID REFERENCES auth.users(id)
);
```

### `attendance`
```sql
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
  UNIQUE (child_id, date)  -- one record per child per day
);
```

### `lesson_plans`
```sql
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
```

### `daily_reports`
```sql
CREATE TABLE daily_reports (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  child_id    UUID REFERENCES children(id) NOT NULL,
  teacher_id  UUID REFERENCES auth.users(id) NOT NULL,
  center_id   UUID REFERENCES centers(id) NOT NULL,
  date        DATE NOT NULL,
  text        TEXT DEFAULT '',
  image_urls  JSONB DEFAULT '[]' NOT NULL,  -- array of Supabase Storage URLs; suggest max 5 (TBC)
  created_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  created_by  UUID REFERENCES auth.users(id),
  updated_by  UUID REFERENCES auth.users(id),
  UNIQUE (child_id, date)  -- one report per child per day
);
```

### Row Level Security (RLS) — RBAC at the database layer

```sql
-- Enable RLS on all tables
ALTER TABLE profiles      ENABLE ROW LEVEL SECURITY;
ALTER TABLE children      ENABLE ROW LEVEL SECURITY;
ALTER TABLE schedules     ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance    ENABLE ROW LEVEL SECURITY;
ALTER TABLE lesson_plans  ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_reports ENABLE ROW LEVEL SECURITY;

-- Helper: get current user's role
CREATE OR REPLACE FUNCTION current_role_name() RETURNS TEXT AS $$
  SELECT role FROM profiles WHERE id = auth.uid();
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- profiles: users read their own; directors read all in their center
CREATE POLICY "profiles_select" ON profiles FOR SELECT
  USING (id = auth.uid() OR current_role_name() = 'director');

-- children: parents see their linked children; teachers see their class; directors see all
CREATE POLICY "children_select" ON children FOR SELECT
  USING (
    current_role_name() = 'director'
    OR teacher_id = auth.uid()
    OR EXISTS (SELECT 1 FROM children_parents WHERE child_id = children.id AND parent_id = auth.uid())
  );

-- attendance: teachers write their class; parents read their child's; directors read all
CREATE POLICY "attendance_select" ON attendance FOR SELECT
  USING (
    current_role_name() = 'director'
    OR created_by = auth.uid()
    OR EXISTS (SELECT 1 FROM children_parents WHERE child_id = attendance.child_id AND parent_id = auth.uid())
  );
CREATE POLICY "attendance_insert" ON attendance FOR INSERT
  WITH CHECK (current_role_name() = 'teacher');
CREATE POLICY "attendance_update" ON attendance FOR UPDATE
  USING (current_role_name() = 'teacher' AND created_by = auth.uid());

-- lesson_plans: teachers write their own; directors read all
CREATE POLICY "lesson_plans_select" ON lesson_plans FOR SELECT
  USING (teacher_id = auth.uid() OR current_role_name() = 'director');
CREATE POLICY "lesson_plans_insert" ON lesson_plans FOR INSERT
  WITH CHECK (current_role_name() = 'teacher');
CREATE POLICY "lesson_plans_update" ON lesson_plans FOR UPDATE
  USING (current_role_name() = 'teacher' AND teacher_id = auth.uid());

-- daily_reports: teachers write; parents read their child's
CREATE POLICY "daily_reports_select" ON daily_reports FOR SELECT
  USING (
    teacher_id = auth.uid()
    OR current_role_name() = 'director'
    OR EXISTS (SELECT 1 FROM children_parents WHERE child_id = daily_reports.child_id AND parent_id = auth.uid())
  );
CREATE POLICY "daily_reports_insert" ON daily_reports FOR INSERT
  WITH CHECK (current_role_name() = 'teacher');
CREATE POLICY "daily_reports_update" ON daily_reports FOR UPDATE
  USING (current_role_name() = 'teacher' AND teacher_id = auth.uid());
```

---

## 5. App Architecture

### Single app, role-based routing

One Flutter app. After Supabase Auth login, the app reads `profiles.role` from PostgreSQL and navigates to the correct shell:

```
main.dart
  └── AuthGate
        ├── LoginScreen
        └── RoleRouter
              ├── ParentShell      → BottomNav: Schedule | Attendance | Reports
              ├── TeacherShell     → BottomNav: Schedule | Attendance | Lesson Plans | Daily Reports
              └── DirectorShell   → BottomNav: Teachers | Schedules | Lesson Plans | Attendance
```

### Folder structure

```
lib/
  main.dart
  core/
    auth/
      auth_gate.dart
      role_router.dart
    models/
      user_model.dart
      child_model.dart
      attendance_model.dart
      schedule_model.dart
      lesson_plan_model.dart
      daily_report_model.dart
    services/
      auth_service.dart
      attendance_service.dart
      schedule_service.dart
      lesson_plan_service.dart
      daily_report_service.dart
  features/
    auth/
      login_screen.dart
    parent/
      parent_shell.dart
      screens/
        child_schedule_screen.dart
        child_attendance_screen.dart
        daily_reports_screen.dart
    teacher/
      teacher_shell.dart
      screens/
        teacher_schedule_screen.dart
        attendance_screen.dart
        lesson_plan_screen.dart
        daily_report_create_screen.dart
    director/
      director_shell.dart
      screens/
        all_teachers_screen.dart
        all_schedules_screen.dart
        all_lesson_plans_screen.dart
        all_attendance_screen.dart
        manage_children_screen.dart
        manage_teachers_screen.dart
  shared/
    widgets/
      app_bottom_nav.dart
      loading_indicator.dart
      error_widget.dart
```

---

## 6. Feature Descriptions

### 6.1 Authentication
- Firebase Auth with email + password
- On first login, Director manually creates teacher and parent accounts via Admin panel
- Role is set in Firestore by the Director, never self-assigned
- Session persists across app restarts (Firebase handles token refresh)

### 6.2 Schedules
- Children have a weekly schedule (days + time slots + label e.g. "Nap", "Lunch", "Art")
- Teachers have their own weekly schedule (days + time slots + class/room)
- Both child schedules and teacher schedules are created and edited by the Director only
- Director can view all teacher schedules on one screen
- Parents can view their child's schedule (read-only)
- Teachers can view their own schedule (read-only)

### 6.3 Attendance
- Teacher opens the attendance screen, sees the list of children in their class
- Marks each child: Present / Absent / Late / Excused
- One record per child per day — re-opening the screen shows existing marks for editing
- Director can filter and view attendance across all children and dates

### 6.4 Daily Reports
- Teacher creates one report per child per day
- Report contains free-text and images (uploaded to Firebase Storage; image limit per report to be confirmed — suggest starting with 5)
- Parent sees all reports for their child, sorted by date (newest first)
- Reports are read-only for parents

### 6.5 Lesson Plans
- Teacher writes a lesson plan per day (title + content)
- Director can browse all teachers' lesson plans, filtered by teacher or date
- Lesson plans are read-only for the Director

### 6.6 Director / Admin Panel
- Add / edit / deactivate teacher accounts
- Enroll children, assign to rooms and primary teacher
- Create parent accounts and link to a child
- View all schedules, attendance records, and lesson plans across the center
- Manage center settings (center name, rooms)

---

## 7. Navigation Flow

```
Login
  ↓
Role Router
  ↓
┌─────────────────────────────────────────────┐
│ PARENT                                       │
│  Tab 1: Child Schedule (weekly grid)         │
│  Tab 2: Child Attendance (calendar view)     │
│  Tab 3: Daily Reports (list → detail)        │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│ TEACHER                                      │
│  Tab 1: My Schedule (weekly grid)            │
│  Tab 2: Attendance (today's class list)      │
│  Tab 3: Lesson Plans (list → create/edit)    │
│  Tab 4: Daily Reports (create per child)     │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│ DIRECTOR                                     │
│  Tab 1: Teachers (list → profile)            │
│  Tab 2: Schedules (all teachers)             │
│  Tab 3: Lesson Plans (all teachers)          │
│  Tab 4: Attendance (all children, all dates) │
│  FAB: + Add Teacher / + Enroll Child         │
└─────────────────────────────────────────────┘
```

---

## 8. Error Handling

- All Firestore reads wrapped in try/catch with a shared `ErrorWidget` fallback
- Offline: Firestore's built-in local cache keeps read data available; writes are queued and synced when back online
- Image uploads show progress indicator; failed uploads surface a retry option
- Auth errors (wrong password, account disabled) shown as inline form errors, not dialogs

---

## 9. Out of Scope (Future Iterations)

The following are intentionally excluded from this version:

- Billing and invoicing
- In-app messaging between teacher and parent
- Push notifications (can be added once core is stable)
- Waitlist management
- Medication administration logs
- Document storage (immunization records)
- Multi-center management under one Director account
- Granular permission splits between Director and Admin roles

---

## 10. Build Phases

| Phase | Features | Target |
|---|---|---|
| 1 | Auth + RBAC + Schedules + Attendance | Core usable by teachers |
| 2 | Daily Reports (text + images) | Parents get value |
| 3 | Lesson Plans + Director panel | Directors can monitor |
| 4 | Web build + polish | Broader access |
