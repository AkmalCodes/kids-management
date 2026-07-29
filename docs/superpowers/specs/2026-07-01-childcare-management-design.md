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
| Transactional email | Custom SMTP (e.g. Resend) — **not yet configured** | Required for reliable invite/recovery emails; see §6.6 note |
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
  id                UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  role              TEXT NOT NULL CHECK (role IN ('parent', 'teacher', 'director')),
  name              TEXT NOT NULL,
  phone             TEXT DEFAULT '',
  center_id         UUID REFERENCES centers(id),
  must_set_password BOOLEAN NOT NULL DEFAULT false,  -- true for invited accounts until they choose a password (§6.6a)
  avatar_path       TEXT,  -- profile picture in the private 'avatars' bucket (§6.7), null if unset
  email             TEXT,  -- denormalized copy of auth.users.email (§6.6) so directors can display it; auth.users isn't readable cross-user from the client
  created_at        TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at        TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  created_by        UUID REFERENCES auth.users(id),
  updated_by        UUID REFERENCES auth.users(id)
);

-- Each lets a user update just their own row's specific fields without a
-- broad self-UPDATE policy (which could let them change their own role).
-- SECURITY DEFINER; each only ever touches the caller's own row.
CREATE OR REPLACE FUNCTION complete_password_setup() RETURNS void AS $$
  UPDATE profiles SET must_set_password = false, updated_at = now() WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION set_avatar_path(new_path TEXT) RETURNS void AS $$
  UPDATE profiles SET avatar_path = new_path, updated_at = now() WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER;

-- Self-edit of own name/phone (any role), from the Profile tab's "Profile
-- details" screen. Directors editing OTHERS go through profiles_update_director.
CREATE OR REPLACE FUNCTION update_own_profile(new_name TEXT, new_phone TEXT)
RETURNS profiles AS $$
  UPDATE profiles SET name = new_name, phone = new_phone, updated_at = now()
  WHERE id = auth.uid() RETURNING *;
$$ LANGUAGE sql SECURITY DEFINER;
```
> Supabase Auth manages the email + password in `auth.users`. `profiles` holds everything else. The `id` in `profiles` is the same UUID as in `auth.users`.

### `children`
```sql
CREATE TABLE children (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name        TEXT NOT NULL,
  dob         DATE NOT NULL,  -- age is derived from this in the UI, not stored
  center_id   UUID REFERENCES centers(id) NOT NULL,
  class_name  TEXT DEFAULT '',  -- free-text label (formerly "room_id"); legacy, superseded by class_id
  teacher_id  UUID REFERENCES auth.users(id),  -- drives attendance/report visibility (a teacher's own children)
  class_id    UUID REFERENCES classes(id),  -- §6.8: the class the child is in; its teacher drives the parent's schedule view
  allergies   TEXT DEFAULT '',
  notes       TEXT DEFAULT '',
  avatar_path TEXT,  -- child photo in the private 'child-avatars' bucket (§6.6), null if unset
  enrolled_at DATE DEFAULT CURRENT_DATE NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  created_by  UUID REFERENCES auth.users(id),
  updated_by  UUID REFERENCES auth.users(id)
);
```

### `classes` (§6.8)
```sql
CREATE TABLE classes (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name        TEXT NOT NULL,
  teacher_uid UUID REFERENCES auth.users(id),  -- the teacher assigned to this class
  center_id   UUID REFERENCES centers(id) NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  created_by  UUID REFERENCES auth.users(id),
  updated_by  UUID REFERENCES auth.users(id)
);
```
> **Additive design (decided, not the only option):** `class_id` was added *alongside* the existing `children.teacher_id` rather than replacing it — `teacher_id` still drives attendance/daily-report visibility (a teacher sees "their" children), while `class_id → classes.teacher_uid` drives what schedule a parent sees. There is deliberate redundancy (teacher_id, class_name, and class_id all touch "who teaches this child"); consolidating is a future decision. Class creation/assignment has no UI yet — done via SQL (a director class-management screen is a planned follow-up). RLS: directors manage classes; teachers see their own; a parent sees the class their child is in.

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
  type       TEXT NOT NULL CHECK (type IN ('child', 'teacher', 'class')),  -- 'class' is the live one (§6.8); teacher/child legacy
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

### Storage: `avatars` bucket
Private bucket for **user** profile pictures, one file per user at `<user_id>/avatar.jpg` (§6.7). RLS allows the owner (`storage.foldername(objects.name)[1] = auth.uid()::text`) **or a director** to insert/update/select — so a director can change a teacher's/parent's photo from the person-detail screen. Displayed via a session-cached signed URL (`signedAvatarUrlProvider`).

### Storage: `child-avatars` bucket
Private bucket for **child** photos, one file per child at `<child_id>/avatar.jpg` (§6.6). Children have no auth account, so they can't use the user `avatars` bucket. Only directors insert/update; select is available to any director, the child's own teacher, or a linked parent. Displayed via `signedChildAvatarUrlProvider`.

### Storage: `daily-report-images` bucket
Private bucket for **daily-report** photos (§6.4), path `<child_id>/<date>/<n>.jpg` (multiple photos per report). The child's teacher inserts; select is available to that teacher, any director, or a linked parent (so parents see them in their feed). Displayed via `signedReportImageUrlProvider`.

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
  image_paths JSONB DEFAULT '[]' NOT NULL,  -- array of storage paths in the daily-report-images bucket (signed on display)
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
-- Directors can edit any profile (name/phone, via the person-detail screen).
-- Scoped to directors so a non-director can't self-escalate their role --
-- that's why regular-user self-edits (avatar, password flag) go through
-- narrow SECURITY DEFINER RPCs instead of a broad self-update policy.
CREATE POLICY "profiles_update_director" ON profiles FOR UPDATE
  USING (current_role_name() = 'director');

-- children: parents see their linked children; teachers see their class; directors see all
CREATE POLICY "children_select" ON children FOR SELECT
  USING (
    current_role_name() = 'director'
    OR teacher_id = auth.uid()
    OR EXISTS (SELECT 1 FROM children_parents WHERE child_id = children.id AND parent_id = auth.uid())
  );
-- children: only directors create/edit records (enrollment UI, §6.6)
CREATE POLICY "children_insert" ON children FOR INSERT
  WITH CHECK (current_role_name() = 'director');
CREATE POLICY "children_update" ON children FOR UPDATE
  USING (current_role_name() = 'director');

-- children_parents: RLS must be enabled on this junction table (it wasn't
-- originally). Directors manage links; a parent can read their own.
ALTER TABLE children_parents ENABLE ROW LEVEL SECURITY;
CREATE POLICY "children_parents_select" ON children_parents FOR SELECT
  USING (current_role_name() = 'director' OR parent_id = auth.uid());
CREATE POLICY "children_parents_insert" ON children_parents FOR INSERT
  WITH CHECK (current_role_name() = 'director');
CREATE POLICY "children_parents_delete" ON children_parents FOR DELETE
  USING (current_role_name() = 'director');

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
    -- §6.8: class-owned schedules — the class's teacher, and parents of a child in it
    OR (type = 'class' AND EXISTS (
      SELECT 1 FROM classes WHERE classes.id = schedule_entries.ref_id AND classes.teacher_uid = auth.uid()
    ))
    OR (type = 'class' AND EXISTS (
      SELECT 1 FROM classes cl
      JOIN children c ON c.class_id = cl.id
      JOIN children_parents cp ON cp.child_id = c.id
      WHERE cl.id = schedule_entries.ref_id AND cp.parent_id = auth.uid()
    ))
  );
CREATE POLICY "schedule_entries_insert" ON schedule_entries FOR INSERT
  WITH CHECK (
    current_role_name() = 'director'
    OR (current_role_name() = 'teacher' AND type = 'teacher' AND ref_id = auth.uid())  -- legacy
    OR (type = 'class' AND EXISTS (
      SELECT 1 FROM classes WHERE classes.id = schedule_entries.ref_id AND classes.teacher_uid = auth.uid()
    ))
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
      class_group.dart              -- the `classes` table (named ClassGroup; `Class` is reserved) (§6.8)
    services/
      child_service.dart
      teacher_service.dart
      class_service.dart            -- fetch classes + resolve a class's teacher (§6.8)
      schedule_service.dart
      attendance_service.dart
      photo_capture_service.dart    -- thin ImagePicker wrapper, injectable/mockable
      user_management_service.dart  -- calls the create-user Edge Function (invite teacher/parent)
      profile_service.dart          -- user avatar upload/signed-url + set/update RPCs + director edit (§6.7)
      daily_report_service.dart     -- fetch/save reports + report-image upload/signed-url (§6.4)
      lesson_plan_service.dart      -- (not yet built)
    theme/
      app_theme.dart                -- single seed color + font (Nunito via google_fonts) + tinted top/bottom bars, cascades app-wide
  features/
    auth/
      login_screen.dart             -- includes "Forgot password?" -> ForgotPasswordScreen
      set_password_screen.dart      -- invite completion + password recovery (§6.6a / §6.7a)
      forgot_password_screen.dart   -- sends the recovery email (§6.7a)
    profile/
      profile_screen.dart           -- shared account settings tab, all roles (§6.7)
      change_password_screen.dart   -- change password while signed in (§6.7)
      person_detail_screen.dart     -- view/edit a person's name/phone/photo; self or director-edits-other (§6.6/§6.7)
    parent/
      parent_shell.dart
      screens/
        child_schedule_screen.dart
        child_attendance_screen.dart
        child_reports_screen.dart   -- parent's daily-report feed (§6.4)
    teacher/
      teacher_shell.dart
      screens/
        teacher_schedule_screen.dart
        mark_attendance_screen.dart
        teacher_reports_screen.dart -- class list -> report editor (§6.4)
        daily_report_edit_screen.dart -- write/edit one child's daily report (§6.4)
        lesson_plan_screen.dart     -- (not yet built)
    director/
      director_shell.dart
      screens/
        director_attendance_screen.dart
        director_schedules_screen.dart  -- searchable teacher list -> PersonScheduleScreen
        person_schedule_screen.dart     -- reusable editable agenda view for any teacher/child
        people_screen.dart              -- Teachers | Children sub-tabs (§6.6)
        manage_teachers_screen.dart     -- teacher list (tap -> PersonDetailScreen) + invite-a-teacher
        manage_children_screen.dart     -- child list (tap -> ChildDetailScreen) + invite-a-parent
        enroll_child_screen.dart        -- child record + first parent invite in one form
        child_detail_screen.dart        -- director view/edit of one child + parent contacts (§6.6)
  shared/
    screens/
      day_schedule_screen.dart      -- hourly view for one day; owns create/edit/delete
    widgets/
      logout_button.dart
      attendance_status_chip.dart
      signed_photo_thumbnail.dart   -- exchanges a private Storage path for a signed URL, with loading/error states
      signed_avatar.dart            -- round avatar from any bucket's signed-URL provider, with placeholder (§6.6/§6.7)
      avatar_source_sheet.dart      -- shared take-photo/gallery bottom sheet for avatar edits
      person_invite_dialog.dart     -- shared name/email/phone dialog for teacher & parent invites
      schedule_agenda_view.dart     -- week/month toggle, colored event cards
      day_timetable.dart            -- hour grid, tap-to-add/edit, fade-in on new entries
      schedule_entry_form_dialog.dart -- shared create/edit dialog with color picker
supabase/
  functions/
    create-user/index.ts            -- director-only account provisioning (§6.6a)
```

---

## 6. Feature Descriptions

### 6.1 Authentication
- Supabase Auth with email + password
- Directors create teacher and parent accounts in-app via the People tab, which sends an email invite; the invitee sets their own password on first entry (§6.6a). (The very first director account is still seeded manually via the dashboard.)
- Role is set in the `profiles` table by the Director (server-side, in the create-user Edge Function), never self-assigned
- Session persists across app restarts (Supabase handles token refresh)

### 6.2 Schedules
Recurring weekly pattern per person (day-of-week + time, no calendar date) — the same class shows up on every matching weekday, not a one-off dated event.

- Schedules are **class-owned** (`type='class'`, `ref_id = class_id`) — §6.8, so a class's schedule is independent of how many teachers it has.
- **Director**: Schedules tab is a searchable **class** list → lands on that class's editable agenda/day view (tap a day for the hourly timetable, tap a slot / **+** to add, tap an event to edit/delete).
- **Teacher**: manages the schedule of the class they're assigned to (`ClassService.fetchForTeacher`), same editable view.
- **Parent**: read-only view of their child's class schedule (child → `class_id` → `type='class'` entries); falls back to "Not assigned to a class yet".
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
- The photo row's two halves are `Expanded` with an ellipsizing `Flexible` label (not sized to their own intrinsic content width) so the row can't overflow on a narrow screen; same fix applied to the header's date text next to "Attendance" — both surfaced after switching the app font (now Nunito; see folder structure note on `app_theme.dart` below) rendered text wider than the previous default. Covered by a regression test that pumps the screen at a 320px-wide surface
- Signed URLs (see below) are cached per photo path in a Riverpod `FutureProvider.family` (`signedPhotoUrlProvider`) for the app's session, so re-expanding a card reuses the already-fetched URL instead of re-hitting Storage
- Both photos are visible to parents (child's attendance history) and directors (attendance tab), fetched via a signed URL since the Storage bucket is private
- Director can filter and view attendance across all children and dates

### 6.4 Daily Reports — built (teacher write, parent read)
- **Teacher** (Reports tab, `TeacherReportsScreen`): their class as a list; tap a child → `DailyReportEditScreen` to write today's report — free text + photos. One report per child per day, so it opens the existing one to edit or a blank form. Photos upload immediately to the `daily-report-images` bucket; text + image paths persist on Save (via `DailyReportService.saveReport`, insert-or-update on the child+date row).
- **Parent** (Reports tab, `ChildReportsScreen`): for each linked child, a read-only feed of daily reports newest-first — the teacher's note + photo thumbnails (signed URLs).
- **Director**: reads all via RLS, but no dedicated reports screen yet (⬜ could add a browse view later).
- Data: `daily_reports` table (one row per child+date), image paths stored on the row, photos in the private `daily-report-images` bucket.

### 6.5 Lesson Plans — not yet built
- Teacher writes a lesson plan per day (title + content)
- Director can browse all teachers' lesson plans, filtered by teacher or date
- Lesson plans are read-only for the Director

### 6.6 Director / Admin Panel — partially built
- ✅ View all attendance records, any date (Attendance tab)
- ✅ View/edit any teacher's or child's schedule (Schedules tab, §6.2)
- ✅ **People tab** (Teachers | Children sub-tabs) for account provisioning:
  - Invite a teacher by email
  - Enroll a child and invite its first parent in one form; invite additional parents per child from the Children list
- ✅ **Tap a row to view/edit details:**
  - A child → `ChildDetailScreen`: edit photo (child-avatars bucket), name, date of birth (age is shown, derived), class, class teacher (dropdown), allergies, notes — saved via `ChildService.updateChild` (director-only per `children_update` RLS). Also shows a read-only **Parents** section (each linked parent's name + email, via `ChildService.fetchParentsForChild`).
  - A teacher/parent → `PersonDetailScreen`: edit photo, name and phone. A director editing someone else uses `updatePersonDetails` + `setAvatarPathFor` (director policy); editing yourself uses the self-only `update_own_profile` / `setAvatarPath` RPCs (see §6.7). Email isn't shown (lives on `auth.users`, not readable cross-user from the client).
- ⬜ Deactivate/delete existing accounts (create + edit are built; deletion is still manual via the dashboard)
- ⬜ View all lesson plans across the center (depends on §6.5)
- ⬜ Manage center settings (center name, rooms)

**How account provisioning works (§6.6a):** The Flutter app can never create accounts for other people directly — that needs Supabase's admin API and the service role key, which must stay server-side. So a director's invite calls the **`create-user` Edge Function** (`supabase/functions/create-user`): it verifies the caller is a director via their own JWT, then uses the service role key to `inviteUserByEmail` and insert the `profiles` row (with `must_set_password = true`). The invite email's link deep-links back into the app via a custom URL scheme (`com.example.test_flutter://login-callback/`, registered in AndroidManifest.xml + iOS Info.plist and allow-listed in the dashboard's Auth → Redirect URLs). On first entry the invited user lands on `SetPasswordScreen` (routed by `AuthGate` when `must_set_password`), sets a password, and the flag is cleared via the `complete_password_setup()` SECURITY DEFINER RPC (avoids granting a broad `profiles` UPDATE policy that could let users change their own role).

> ⚠️ **Production requirement — custom SMTP not yet configured.** Invite and password-recovery emails currently go through Supabase's built-in email sender, which is a shared, heavily rate-limited service intended only for development (hitting "email rate limit exceeded" after a few test invites is expected). Before inviting real teachers/parents, a custom SMTP provider (e.g. Resend, SendGrid) **must** be configured in Dashboard → Project Settings → Authentication → SMTP Settings. Supabase generates the invite/recovery link and its token; the SMTP provider is what actually delivers the email reliably to real inboxes (analogous to why production PHP uses PHPMailer + a real mail service instead of the built-in `mail()`).

### 6.7 Profile / Account settings — all roles
Every role has a **Profile** tab (shared `ProfileScreen`) showing their avatar, name, email (read from the auth session, not the profiles row), and role, with actions to:
- **Change photo** — take or pick a photo, uploaded to the private `avatars` bucket; the path is saved via the `set_avatar_path()` RPC and displayed through a signed URL.
- **Profile details** — opens the shared `PersonDetailScreen` for the current user, to edit name/phone/photo (self-edit path: `update_own_profile` / `setAvatarPath`). The same screen is reused by the director's People tab for editing others.
- **Change password** — `ChangePasswordScreen` (already signed in, so just captures a new password via `updateUser`; distinct from the invite/recovery `SetPasswordScreen` because it pops back on success instead of relying on `AuthGate` to re-route).
- **Sign out**.

**Forgot password (§6.7a):** `LoginScreen` has a "Forgot password?" link → `ForgotPasswordScreen`, which calls `resetPasswordForEmail` with the same `com.example.test_flutter://login-callback/` deep-link `redirectTo`. Opening that link fires an `AuthChangeEvent.passwordRecovery` (exposed as `passwordRecoveryProvider`); `AuthGate` then shows `SetPasswordScreen` in recovery mode (`clearMustSetPasswordFlag: false`) regardless of the user's normal routing. Completing the password update fires `userUpdated`, which drops back out of recovery mode automatically.

### 6.8 Classes — partially built (schema + parent-schedule link)
A `classes` table groups children under an assigned teacher, added **additively** alongside the existing `children.teacher_id` (see the `classes` schema note in §4 for the reasoning).
- ✅ Schema: `classes` (id, name, teacher_uid, center_id) + `children.class_id` + RLS (directors manage; teachers see own; parents see their child's class).
- ✅ **Class-owned schedules** (`type='class'`, `ref_id=class_id`): director edits per class (Schedules tab = class list), teacher edits their assigned class's schedule, parent reads their child's class schedule. Chosen over teacher-owned so multiple teachers per class (future) has one schedule. Old `type='teacher'` entries are orphaned.
- ⬜ **No class-management UI yet** — creating classes and assigning teachers/children is done via SQL. A director class-management screen (and deciding whether `class_id` should supersede `teacher_id`/`class_name`) is a planned follow-up.
- 🔭 **Future — multiple teachers per class:** a class may eventually have >1 teacher. Plan: a `class_teachers (class_id, teacher_id)` junction (many-to-many), backfilled from `classes.teacher_uid`. This is why schedules are being moved to belong to the **class**, not the teacher (below) — so "whose schedule does the parent see" has one answer regardless of teacher count.
- 🔭 **Future (not designed yet):** how **lessons** relate to classes and schedule events — deferred brainstorm.

---

## 7. Navigation Flow

```
Login ──("Forgot password?")──► ForgotPasswordScreen
  ↓
AuthGate  (recovery link → SetPasswordScreen; invited & must_set_password → SetPasswordScreen)
  ↓
Role Router
  ↓
┌─────────────────────────────────────────────┐
│ PARENT                                       │
│  Tab 1: Schedule (agenda: week/month toggle) │
│  Tab 2: Attendance (per-child history)       │
│  Tab 3: Reports (daily-report feed)          │
│  Tab 4: Profile (avatar, password, sign out) │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│ TEACHER                                      │
│  Tab 1: Schedule (agenda → day timetable,    │
│          create/edit/delete own events)      │
│  Tab 2: Attendance (today's class list)      │
│  Tab 3: Lesson Plans — not yet built         │
│  Tab 4: Reports (class list → report editor) │
│  Tab 5: Profile (avatar, password, sign out) │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│ DIRECTOR                                     │
│  Tab 1: People (Teachers | Children sub-tabs)│
│  Tab 2: Schedules (search a teacher → their  │
│          editable agenda/day view)           │
│  Tab 3: Lesson Plans — not yet built          │
│  Tab 4: Attendance (all children, any date)  │
│  Tab 5: Profile (avatar, password, sign out) │
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
| 4 | Director account/enrollment management — People tab: invite teachers, enroll children + invite parents, via a `create-user` Edge Function + invite/set-password deep-link flow (§6.6a) | ✅ Done (⚠️ needs custom SMTP before real use) |
| 5 | Profile/settings tab (avatar, change password, sign out) + Forgot Password on login, with password-recovery deep-link handling (§6.7) | ✅ Done |
| 5.5 | Profile pictures shown as avatars everywhere (attendance cards, People lists, parent contacts) | ✅ Done |
| 6 | Daily Reports (text + images) — teacher write, parent read (§6.4) | ✅ Done |
| 7 | Lesson Plans | ⬜ Not started |
| 8 | Play Store release prep (see §11) | ⬜ Not started |
| 9 | Web build + polish | ⬜ Not started |

## 11. Play Store release prep (not started)

Tracked for later; none of this is code-complete yet. Blocking items are called out.

- ⚠️ **Rename `applicationId`** from the placeholder `com.example.test_flutter` to a real reverse-domain id (e.g. `com.akmalcodes.childcaremanager`) — Google Play rejects `com.example`. **Coordinated change**: the auth deep-link scheme (`com.example.test_flutter://login-callback/`) is duplicated in `AndroidManifest.xml`, `ios/Runner/Info.plist`, the `create-user` Edge Function, `auth_service.dart`, and the Supabase dashboard **Redirect URLs** — all must move together or invites/password-reset break.
- Set a real app **display name** ("Childcare Manager") and a **launcher icon** (e.g. via `flutter_launcher_icons`).
- **Play App Signing**: create an upload keystore (`keytool`), keep the keystore + passwords backed up outside the repo, wire a release signing config.
- Build: `flutter build appbundle --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...` (anon key is safe to ship; RLS protects the data).
- Play Console listing: store listing assets, content rating, **Data safety form + privacy policy URL** (we store emails and children's photos), target-audience = adults (users are teachers/parents/directors).
- Distribution: **Internal testing track** is the portfolio path (shareable install link, minimal review). A full production launch of a real childcare app carries children's-data privacy weight (COPPA/GDPR-K) — use dummy data for the portfolio demo.
- New personal developer accounts must run a closed test with a minimum number of testers (~12) for 14 days before production access (doesn't affect internal testing).
