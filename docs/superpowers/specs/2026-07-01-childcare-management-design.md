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
| View own schedule | — | ✅ | ✅ |
| View any teacher's schedule | — | ✅ | ✅ |
| Create/edit/delete events on own schedule | — | ✅ | ✅ |
| Create/edit/delete events on any schedule | — | — | ✅ |
| Edit/delete an event someone else created | — | — (unless director) | ✅ |
| Create / edit lesson plans | — | ✅ | — |
| Create daily reports (text + images) | — | ✅ | — |
| Mark attendance | — | ✅ | — |
| View all lesson plans | — | — | ✅ |
| View all attendance records | — | — | ✅ |
| Manage teachers (add / edit / remove) | — | — | ✅ |
| Manage children (enrollment, room assignment) | — | — | ✅ |
| Manage parent accounts | — | — | ✅ |
| Manage center settings | — | — | ✅ |

> **Note:** Director and Admin are the same role for now. Further permission granularity can be added in a future iteration.
>
> **Schedule permissions changed from the original design** (which had schedules as Director-only): teachers now manage their own schedule directly, and can see — but not edit — every other teacher's schedule. Edit/delete rights on a specific event belong to whoever created it, or any director, regardless of who created it. See §6.2 and the `schedule_entries` RLS policies below.

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

### `schedule_entries`
> **Superseded design note:** the original plan stored a whole person's week as one row with a `JSONB` array of entries (`schedules` table). That was replaced with **one row per event** once per-event edit/delete permissions were needed (§6.2) — a single JSONB blob can't carry a different `created_by` per entry, but a normal row can.
```sql
CREATE TABLE schedule_entries (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  type       TEXT NOT NULL CHECK (type IN ('child', 'teacher')),
  ref_id     UUID NOT NULL,  -- child id or teacher user id this entry belongs to
  center_id  UUID REFERENCES centers(id) NOT NULL,
  day        TEXT NOT NULL CHECK (day IN ('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')),
  start_time TEXT NOT NULL,  -- 'HH:MM'
  end_time   TEXT NOT NULL,
  label      TEXT NOT NULL,
  color      TEXT NOT NULL DEFAULT '26A69A',  -- bare 6-digit hex, no '#'; picked from a fixed palette in the UI
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  created_by UUID REFERENCES auth.users(id),
  updated_by UUID REFERENCES auth.users(id)
);
```

### `attendance`
```sql
CREATE TABLE attendance (
  id                    UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  child_id              UUID REFERENCES children(id) NOT NULL,
  center_id             UUID REFERENCES centers(id) NOT NULL,
  date                  DATE NOT NULL,
  status                TEXT NOT NULL CHECK (status IN ('present', 'absent', 'late', 'excused')),
  notes                 TEXT DEFAULT '',
  photo_path            TEXT,  -- optional check-in photo, Storage path in `attendance-photos`
  belongings_photo_path TEXT,  -- optional photo of the child's belongings/clothes for the day
  created_at            TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at            TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  created_by            UUID REFERENCES auth.users(id),
  updated_by            UUID REFERENCES auth.users(id),
  UNIQUE (child_id, date)  -- one record per child per day
);
```
> Both photo fields are entirely optional and independent of status and of each other — marking a child Present never requires a photo. Photos are attached via dedicated `attachCheckInPhoto`/`attachBelongingsPhoto` calls that touch only their own column, so a later status change never clobbers a photo taken earlier. One photo of each kind per child per day (overwritten via `upsert` on retake), not a multi-photo gallery — kept simple given Storage's per-file cost.

### Storage: `attendance-photos` bucket
Private bucket (not public — a stored path can't be rendered directly; the app exchanges it for a `createSignedUrl` time-limited URL whenever a photo is displayed). Paths are `<child_id>/<date>.jpg` (check-in) and `<child_id>/<date>-belongings.jpg` (belongings), so `storage.foldername(objects.name)[1]` recovers the child for RLS checks — must be qualified as `objects.name` since `children` also has its own `name` column that would otherwise shadow it inside the `EXISTS` subquery. Teachers can insert/update only for children in their own class; select is available to that same teacher, any director, or a linked parent.

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
ALTER TABLE profiles         ENABLE ROW LEVEL SECURITY;
ALTER TABLE children         ENABLE ROW LEVEL SECURITY;
ALTER TABLE schedule_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance       ENABLE ROW LEVEL SECURITY;
ALTER TABLE lesson_plans     ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_reports    ENABLE ROW LEVEL SECURITY;

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

-- schedule_entries: director sees/edits everything; teachers see every
-- teacher's schedule but can only create on their own, and can only
-- edit/delete an entry they created (director can edit/delete any)
CREATE POLICY "schedule_entries_select" ON schedule_entries FOR SELECT
  USING (
    current_role_name() = 'director'
    OR (type = 'teacher' AND current_role_name() = 'teacher')
    OR (type = 'child' AND EXISTS (
      SELECT 1 FROM children
      WHERE children.id = schedule_entries.ref_id AND children.teacher_id = auth.uid()
    ))
    OR (type = 'child' AND EXISTS (
      SELECT 1 FROM children_parents
      WHERE children_parents.child_id = schedule_entries.ref_id AND children_parents.parent_id = auth.uid()
    ))
  );
CREATE POLICY "schedule_entries_insert" ON schedule_entries FOR INSERT
  WITH CHECK (
    current_role_name() = 'director'
    OR (current_role_name() = 'teacher' AND type = 'teacher' AND ref_id = auth.uid())
  );
CREATE POLICY "schedule_entries_update" ON schedule_entries FOR UPDATE
  USING (current_role_name() = 'director' OR created_by = auth.uid());
CREATE POLICY "schedule_entries_delete" ON schedule_entries FOR DELETE
  USING (current_role_name() = 'director' OR created_by = auth.uid());

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

-- attendance-photos Storage bucket: private; paths are "<child_id>/..." so
-- storage.foldername(objects.name)[1] recovers the child_id for the check
-- below. Must be qualified as objects.name, not bare `name` -- `children`
-- also has its own `name` column (the child's name), and inside the EXISTS
-- subquery an unqualified `name` silently binds to that instead of the
-- storage object's path, which made every insert/update fail RLS silently.
CREATE POLICY "attendance_photos_teacher_insert"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'attendance-photos'
  AND current_role_name() = 'teacher'
  AND EXISTS (
    SELECT 1 FROM children
    WHERE children.id::text = (storage.foldername(objects.name))[1] AND children.teacher_id = auth.uid()
  )
);
CREATE POLICY "attendance_photos_teacher_update"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'attendance-photos'
  AND current_role_name() = 'teacher'
  AND EXISTS (
    SELECT 1 FROM children
    WHERE children.id::text = (storage.foldername(objects.name))[1] AND children.teacher_id = auth.uid()
  )
);
CREATE POLICY "attendance_photos_select"
ON storage.objects FOR SELECT
USING (
  bucket_id = 'attendance-photos'
  AND (
    current_role_name() = 'director'
    OR EXISTS (
      SELECT 1 FROM children
      WHERE children.id::text = (storage.foldername(objects.name))[1] AND children.teacher_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM children_parents
      WHERE children_parents.child_id::text = (storage.foldername(objects.name))[1]
        AND children_parents.parent_id = auth.uid()
    )
  )
);

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

Actual structure as of this writing — `(not yet built)` marks planned files that don't exist yet:

```
lib/
  main.dart
  core/
    auth/
      auth_gate.dart
      auth_service.dart
      role_router.dart
    constants/
      schedule_colors.dart          -- shared color palette (picker + display)
    models/
      app_user.dart
      child.dart
      attendance.dart
      schedule.dart                 -- ScheduleEntry: one row per event, not a whole-week blob
      lesson_plan.dart              -- model exists; no service/UI yet
      daily_report.dart             -- model exists; no service/UI yet
    services/
      child_service.dart
      teacher_service.dart
      schedule_service.dart
      attendance_service.dart
      photo_capture_service.dart    -- thin ImagePicker wrapper, injectable/mockable
      lesson_plan_service.dart      -- (not yet built)
      daily_report_service.dart     -- (not yet built)
    theme/
      app_theme.dart                -- single seed color, cascades app-wide
  features/
    auth/
      login_screen.dart
    parent/
      parent_shell.dart
      screens/
        child_schedule_screen.dart
        child_attendance_screen.dart
        daily_reports_screen.dart   -- (not yet built)
    teacher/
      teacher_shell.dart
      screens/
        teacher_schedule_screen.dart
        mark_attendance_screen.dart
        lesson_plan_screen.dart     -- (not yet built)
        daily_report_create_screen.dart -- (not yet built)
    director/
      director_shell.dart
      screens/
        director_attendance_screen.dart
        director_schedules_screen.dart  -- searchable teacher list -> PersonScheduleScreen
        person_schedule_screen.dart     -- reusable editable agenda view for any teacher/child
        manage_teachers_screen.dart     -- (not yet built — Teachers tab is still a placeholder)
        manage_children_screen.dart     -- (not yet built)
  shared/
    screens/
      day_schedule_screen.dart      -- hourly view for one day; owns create/edit/delete
    widgets/
      logout_button.dart
      attendance_status_chip.dart
      signed_photo_thumbnail.dart   -- exchanges a private Storage path for a signed URL, with loading/error states
      schedule_agenda_view.dart     -- week/month toggle, colored event cards
      day_timetable.dart            -- hour grid, tap-to-add/edit, fade-in on new entries
      schedule_entry_form_dialog.dart -- shared create/edit dialog with color picker
```

---

## 6. Feature Descriptions

### 6.1 Authentication
- Supabase Auth with email + password
- On first login, Director manually creates teacher and parent accounts via the Supabase dashboard (no in-app admin UI yet — see §6.6)
- Role is set in the `profiles` table by the Director, never self-assigned
- Session persists across app restarts (Supabase handles token refresh)

### 6.2 Schedules
Recurring weekly pattern per person (day-of-week + time, no calendar date) — the same class shows up on every matching weekday, not a one-off dated event.

- **Teacher**: manages their own schedule directly — tap a day to open its hourly timetable, tap an empty slot (or the floating **+** button) to add an event, tap an existing event to edit or delete it. Can also browse (read-only) every other teacher's schedule, for visibility into the team.
- **Director**: full create/edit/delete rights on *any* teacher's or child's schedule, via a searchable teacher picker (Schedules tab) that lands on the same editable agenda/day view teachers use.
- **Parent**: views their child's schedule, read-only.
- **Edit/delete permission on a specific event**: only the person who created it, or any director — enforced by `schedule_entries` RLS, not just the UI (see §4).
- **Display**: week/month toggle agenda view (colored event cards, "No events" for empty days) + a per-day hourly timetable when you tap into a day. Each event has a color, chosen from a fixed palette at creation, saved to the database, and shown identically everywhere it appears.

### 6.3 Attendance
- Teacher opens the attendance screen, sees today's date (`DD/MM/YY Day`) next to the header and a searchable list of children in their class (search bar at the top filters by name, same pattern as the Director's teacher search in §6.2)
- Each child's card starts collapsed, showing only avatar, name, and current status; tapping expands it to the full marking view (status chips, photo capture) and collapses whichever other card was open — only one expanded at a time
- Marks each child: Present / Absent (Late/Excused still exist in the `status` enum and DB check constraint, but aren't offered as choices on this screen)
- One record per child per day — re-opening the screen shows existing marks for editing
- Status taps and photo captures update the UI from the write's returned row instead of re-fetching the whole roster (same round-trip-avoidance as `ScheduleService`'s create/update)
- Once a status is set, the teacher can optionally take a check-in photo and/or a photo of the child's belongings/clothes for the day — both are entirely optional, unrelated to status, and independent of each other. One photo of each kind per child per day
- Tapping a photo slot opens a menu: Take/Retake photo (camera), Choose from gallery, and — once a photo exists — Delete photo (removes both the Storage object and the column reference). Both slots are a fixed size regardless of whether they show the placeholder icon or an existing thumbnail, so the row's layout doesn't shift depending on photo state
- Signed URLs (see below) are cached per photo path in a Riverpod `FutureProvider.family` (`signedPhotoUrlProvider`) for the app's session, so re-expanding a card reuses the already-fetched URL instead of re-hitting Storage
- Both photos are visible to parents (child's attendance history) and directors (attendance tab), fetched via a signed URL since the Storage bucket is private
- Director can filter and view attendance across all children and dates

### 6.4 Daily Reports — not yet built
- Teacher creates one report per child per day
- Report contains free-text and images (uploaded to Supabase Storage; image limit per report to be confirmed — suggest starting with 5)
- Parent sees all reports for their child, sorted by date (newest first)
- Reports are read-only for parents

### 6.5 Lesson Plans — not yet built
- Teacher writes a lesson plan per day (title + content)
- Director can browse all teachers' lesson plans, filtered by teacher or date
- Lesson plans are read-only for the Director

### 6.6 Director / Admin Panel — partially built
- ✅ View all attendance records, any date (Attendance tab)
- ✅ View/edit any teacher's or child's schedule (Schedules tab, §6.2)
- ⬜ Add / edit / deactivate teacher accounts — currently done manually via the Supabase dashboard (Teachers tab is still a placeholder)
- ⬜ Enroll children, assign to rooms and primary teacher — currently done manually via SQL
- ⬜ Create parent accounts and link to a child — currently done manually via SQL
- ⬜ View all lesson plans across the center (depends on §6.5)
- ⬜ Manage center settings (center name, rooms)

---

## 7. Navigation Flow

```
Login
  ↓
Role Router
  ↓
┌─────────────────────────────────────────────┐
│ PARENT                                       │
│  Tab 1: Schedule (agenda: week/month toggle) │
│  Tab 2: Attendance (per-child history)       │
│  Tab 3: Reports — not yet built              │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│ TEACHER                                      │
│  Tab 1: Schedule (agenda → day timetable,    │
│          create/edit/delete own events)      │
│  Tab 2: Attendance (today's class list)      │
│  Tab 3: Lesson Plans — not yet built         │
│  Tab 4: Reports — not yet built               │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│ DIRECTOR                                     │
│  Tab 1: Teachers — not yet built (placeholder)│
│  Tab 2: Schedules (search a teacher → their  │
│          editable agenda/day view)           │
│  Tab 3: Lesson Plans — not yet built          │
│  Tab 4: Attendance (all children, any date)  │
└─────────────────────────────────────────────┘
```

---

## 8. Error Handling

**Currently implemented:**
- Screens using Riverpod's `AsyncValue` (most of them) show a plain `Error: $e` text on failure — functional but not user-friendly; no shared error widget/retry affordance yet
- Auth errors (wrong password) shown as an inline message on the login form, not a dialog
- Attempting to add a schedule event with no `center_id` on the account shows a specific, actionable message instead of silently failing (a real bug caught during manual testing — see git history)

**Not yet implemented (unlike the original Firestore-based plan, Supabase has no built-in offline cache/write queue — this needs to be built deliberately, not assumed):**
- Offline support — no local cache, no queued writes; the app currently requires a live connection
- A shared, styled error widget with a retry button
- Image upload progress/retry (moot until Daily Reports, §6.4, is built)

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

This replaces the original 4-phase plan — actual delivery order ended up more granular once schedules turned out to need per-event CRUD and permissions rather than a single Director-managed blob.

| Phase | Features | Status |
|---|---|---|
| 1 | Auth + RBAC + navigation shell (Supabase) | ✅ Done |
| 2 | Schedules (read-only agenda view) + Attendance (mark/view) | ✅ Done |
| 3 | Schedule entries CRUD — teacher self-manage, director manage any, per-event creator/director edit permission, event colors, Director's searchable Schedules tab | ✅ Done |
| 4 | Daily Reports (text + images) | ⬜ Not started |
| 5 | Lesson Plans | ⬜ Not started |
| 6 | Director account/enrollment management — Teachers tab, child enrollment, parent linking (currently all manual via Supabase dashboard/SQL) | ⬜ Not started |
| 7 | Web build + polish | ⬜ Not started |
