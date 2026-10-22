# KawanKecil (childcare management app) — Design Spec
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
  email             TEXT,  -- copy of auth.users.email (§6.6) so directors can display it; auth.users isn't readable cross-user from the client. Kept current by the sync_profile_email trigger below.
  -- HR / contact details (§6.6b), all optional; editable by the user (self) or a director:
  address                  TEXT,
  dob                      DATE,
  emergency_contact_name   TEXT,
  emergency_contact_phone  TEXT,
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

-- Self-edit of own name/phone + HR fields (any role), from the Profile tab's
-- "Profile details" screen. Directors editing OTHERS go through
-- profiles_update_director. Adding params changes the signature, so the
-- migration DROPs the old (text,text) version first (see §6.6b handoff).
-- Never touches `role`, so a user still can't self-escalate.
CREATE OR REPLACE FUNCTION update_own_profile(
  new_name TEXT, new_phone TEXT, new_address TEXT DEFAULT NULL,
  new_dob DATE DEFAULT NULL, new_emergency_contact_name TEXT DEFAULT NULL,
  new_emergency_contact_phone TEXT DEFAULT NULL)
RETURNS profiles AS $$
  UPDATE profiles SET
    name = new_name, phone = new_phone, address = new_address, dob = new_dob,
    emergency_contact_name = new_emergency_contact_name,
    emergency_contact_phone = new_emergency_contact_phone, updated_at = now()
  WHERE id = auth.uid() RETURNING *;
$$ LANGUAGE sql SECURITY DEFINER;

-- Keep profiles.email in step with the login email (auth.users.email), so a
-- director always sees a correct address (auth.users isn't readable
-- cross-user from the client). Fires on user creation and email change; a
-- one-time backfill seeds existing rows (see §6.6b handoff).
CREATE OR REPLACE FUNCTION sync_profile_email() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE profiles SET email = NEW.email, updated_at = now() WHERE id = NEW.id;
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_email_sync
  AFTER INSERT OR UPDATE OF email ON auth.users
  FOR EACH ROW EXECUTE FUNCTION sync_profile_email();
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
  teacher_uids UUID[] NOT NULL DEFAULT '{}',  -- any number of teachers, all equal (see 2026-09-04-co-teachers-design.md)
  center_id   UUID REFERENCES centers(id) NOT NULL,
  avatar_path TEXT,  -- class photo in the private 'class-avatars' bucket (§6.8), null if unset
  created_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  created_by  UUID REFERENCES auth.users(id),
  updated_by  UUID REFERENCES auth.users(id)
);
```
> **Additive design (decided, not the only option):** `class_id` was added *alongside* the existing `children.teacher_id` rather than replacing it — `teacher_id` still drives attendance/daily-report visibility (a teacher sees "their" children), while `class_id → classes.teacher_uids` drives what schedule a parent sees. There is deliberate redundancy (teacher_id, class_name, and class_id all touch "who teaches this child"); consolidating is a future decision. Class creation/assignment has no UI yet — done via SQL (a director class-management screen is a planned follow-up). RLS: directors manage classes; teachers see their own; a parent sees the class their child is in.

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
  lesson_plan_id UUID REFERENCES lesson_plans(id) ON DELETE SET NULL,  -- §6.5: attached approved plan; its subject shows on the event, tap opens it
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

### `staff_attendance`
```sql
CREATE TABLE staff_attendance (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  staff_id    UUID REFERENCES profiles(id) NOT NULL,
  center_id   UUID REFERENCES centers(id) NOT NULL,
  date        DATE NOT NULL,
  status      TEXT NOT NULL CHECK (status IN ('present', 'absent', 'late', 'excused')),
  notes       TEXT DEFAULT '',
  clock_in_at TIMESTAMPTZ,
  clock_out_at TIMESTAMPTZ,
  created_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  created_by  UUID REFERENCES auth.users(id),
  updated_by  UUID REFERENCES auth.users(id),
  UNIQUE (staff_id, date),
  CONSTRAINT staff_attendance_clock_order
    CHECK (clock_out_at IS NULL OR (clock_in_at IS NOT NULL AND clock_out_at > clock_in_at))
);
```
> Records a teacher's daily attendance. The `status` field mirrors the child `attendance` table; `notes` is optional context. Initially carries just status and notes (§6.6 follow-up); **`clock_in_at` and `clock_out_at`** were added by a later design (see `docs/superpowers/specs/2026-09-02-staff-clock-in-out-design.md`) as nullable TIMESTAMPTZ columns with a CHECK constraint enforcing `clock_out_at > clock_in_at`. A teacher sets both via **Profile → Attendance** (`StaffAttendanceScreen`), each behind a confirm step, and a day locks once both are set. Director RLS: reads/writes any teacher in their center; teacher RLS: reads/writes own row.

### Storage: `attendance-photos` bucket
Private bucket (not public — a stored path can't be rendered directly; the app exchanges it for a `createSignedUrl` time-limited URL whenever a photo is displayed). Paths are `<child_id>/<date>.jpg` (check-in) and `<child_id>/<date>-belongings.jpg` (belongings), so `storage.foldername(objects.name)[1]` recovers the child for RLS checks — must be qualified as `objects.name` since `children` also has its own `name` column that would otherwise shadow it inside the `EXISTS` subquery. Teachers can insert/update only for children in their own class; select is available to that same teacher, any director, or a linked parent.

### Storage: `avatars` bucket
Private bucket for **user** profile pictures, one file per user at `<user_id>/avatar.jpg` (§6.7). RLS allows the owner (`storage.foldername(objects.name)[1] = auth.uid()::text`) **or a director** to insert/update/select — so a director can change a teacher's/parent's photo from the person-detail screen. Displayed via a session-cached signed URL (`signedAvatarUrlProvider`).

### Storage: `child-avatars` bucket
Private bucket for **child** photos, one file per child at `<child_id>/avatar.jpg` (§6.6). Children have no auth account, so they can't use the user `avatars` bucket. Only directors insert/update; select is available to any director, the child's own teacher, or a linked parent. Displayed via `signedChildAvatarUrlProvider`.

### Storage: `class-avatars` bucket
Private bucket for **class** photos, one file per class at `<class_id>/avatar.jpg` (§6.8). Mirrors the child-avatars pattern: only directors insert/update/select. Displayed via `signedClassAvatarUrlProvider`. Shown on the director's Classes list + ClassDetailScreen.

### Storage: `daily-report-images` bucket
Private bucket for **daily-report** photos (§6.4), path `<child_id>/<date>/<n>.jpg` (multiple photos per report). The child's teacher inserts; select is available to that teacher, any director, or a linked parent (so parents see them in their feed). Displayed via `signedReportImageUrlProvider`.

### `subjects` (§6.5 — center-defined lesson categories)
```sql
CREATE TABLE subjects (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  center_id  UUID REFERENCES centers(id) NOT NULL,
  name       TEXT NOT NULL,
  color      TEXT,  -- optional hex for chips
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  created_by UUID REFERENCES auth.users(id),
  updated_by UUID REFERENCES auth.users(id)
);
```

### `lesson_plans` (§6.5)
```sql
CREATE TABLE lesson_plans (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  teacher_id  UUID REFERENCES auth.users(id) NOT NULL,
  center_id   UUID REFERENCES centers(id) NOT NULL,
  title       TEXT NOT NULL,
  content     TEXT DEFAULT '',  -- reusable: plans have no date; they're attached to schedule events (§6.5 incr. 2)
  subject_id  UUID REFERENCES subjects(id) ON DELETE SET NULL,  -- categorization; un-tagged if the subject is deleted
  class_id    UUID REFERENCES classes(id),  -- which class this plan is for (used by the later schedule-integration increment)
  status      TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','submitted','approved','rejected')),  -- approval workflow
  reviewed_by UUID REFERENCES auth.users(id),  -- director who approved/rejected
  reviewed_at TIMESTAMPTZ,
  review_note TEXT,  -- reviewer's note / rejection reason
  created_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  created_by  UUID REFERENCES auth.users(id),
  updated_by  UUID REFERENCES auth.users(id)
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

-- Helper: get current user's role.
-- SECURITY HARDENING (M4): every SECURITY DEFINER function pins
-- `SET search_path = ''` and schema-qualifies its tables (public.*, auth.*),
-- so a malicious object on the caller's search_path (e.g. a pg_temp table
-- shadowing `profiles`) can't hijack a definer function. This applies to ALL
-- the SECURITY DEFINER functions in this spec — current_role_name,
-- complete_password_setup, set_avatar_path, update_own_profile,
-- sync_profile_email, delete_class, delete_child, class_plan_subjects — see
-- the security-hardening SQL handoff for the full set.
CREATE OR REPLACE FUNCTION current_role_name() RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid();
$$;

-- profiles: users read their own; directors read all in their center
CREATE POLICY "profiles_select" ON profiles FOR SELECT
  USING (id = auth.uid() OR current_role_name() = 'director');
-- Directors can edit any profile (name/phone, via the person-detail screen).
-- Scoped to directors so a non-director can't self-escalate their role --
-- that's why regular-user self-edits (avatar, password flag) go through
-- narrow SECURITY DEFINER RPCs instead of a broad self-update policy.
CREATE POLICY "profiles_update_director" ON profiles FOR UPDATE
  USING (current_role_name() = 'director');

-- SECURITY HARDENING (M2): an RLS policy's WITH CHECK can't compare NEW vs OLD,
-- so it can't by itself stop a director from changing a profile's `role` or
-- `center_id` (privilege escalation / cross-center move). Instead we lock it
-- down with COLUMN-LEVEL privileges: the `authenticated` role may only UPDATE
-- the editable columns, never `role`/`center_id`/`email`/`must_set_password`.
-- The SECURITY DEFINER self-edit RPCs (owned by postgres) and the Edge
-- Function's service_role bypass column grants, so legitimate flows still work;
-- role changes must go through a dedicated privileged path.
REVOKE UPDATE ON profiles FROM authenticated;
GRANT UPDATE (name, phone, address, dob, emergency_contact_name,
              emergency_contact_phone, avatar_path, updated_by, updated_at)
  ON profiles TO authenticated;

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
--
-- SECURITY HARDENING (2026-08-11 fix, folded into
-- 2026-08-07-security-hardening.sql): the director clause reads the
-- child's center via child_center(), a SECURITY DEFINER function, NOT a
-- plain `EXISTS (SELECT 1 FROM children ...)`. A direct subquery on
-- `children` runs under children's own RLS (children_select), which queries
-- children_parents back -> infinite recursion ("infinite recursion detected
-- in policy for relation children"). child_center() bypasses RLS (same
-- trick as my_center()/current_role_name()) so the cycle never starts.
ALTER TABLE children_parents ENABLE ROW LEVEL SECURITY;
CREATE POLICY "children_parents_select" ON children_parents FOR SELECT USING (
  parent_id = auth.uid()
  OR (current_role_name() = 'director' AND child_center(child_id) = my_center())
);
CREATE POLICY "children_parents_insert" ON children_parents FOR INSERT WITH CHECK (
  current_role_name() = 'director' AND child_center(child_id) = my_center()
);
CREATE POLICY "children_parents_delete" ON children_parents FOR DELETE USING (
  current_role_name() = 'director' AND child_center(child_id) = my_center()
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
    -- §6.8: class-owned schedules — a teacher on the class, and parents of a child in it
    OR (type = 'class' AND EXISTS (
      SELECT 1 FROM classes WHERE classes.id = schedule_entries.ref_id AND auth.uid() = ANY(classes.teacher_uids)
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
      SELECT 1 FROM classes WHERE classes.id = schedule_entries.ref_id AND auth.uid() = ANY(classes.teacher_uids)
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
-- SECURITY HARDENING (M3): a teacher may only mark attendance for a child in
-- their own class -- not any child in the DB.
CREATE POLICY "attendance_insert" ON attendance FOR INSERT
  WITH CHECK (
    current_role_name() = 'teacher'
    AND EXISTS (SELECT 1 FROM children
                WHERE children.id = attendance.child_id AND children.teacher_id = auth.uid())
  );
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

-- subjects: any authenticated user reads (they show on plans + the schedule);
-- only directors write.
ALTER TABLE subjects ENABLE ROW LEVEL SECURITY;
CREATE POLICY "subjects_select" ON subjects FOR SELECT USING (true);
CREATE POLICY "subjects_insert" ON subjects FOR INSERT
  WITH CHECK (current_role_name() = 'director');
CREATE POLICY "subjects_update" ON subjects FOR UPDATE
  USING (current_role_name() = 'director');
CREATE POLICY "subjects_delete" ON subjects FOR DELETE
  USING (current_role_name() = 'director');

-- lesson_plans: teacher sees/creates own; director sees all. UPDATE is split
-- into two policies so approval can't be forged (§6.5):
--   • a teacher may edit their OWN plan but only to a draft/submitted status
--     (WITH CHECK) — so a teacher can never self-approve;
--   • a director may set ANY status on ANY plan.
-- DELETE: teacher own, or director.
-- Own plans + director; PLUS approved plans readable by a connected role (a
-- teacher on the class or a parent of a child in the class) so an attached plan
-- opens from the schedule (§6.5 incr. 2). Unapproved stay teacher/director-only.
CREATE POLICY "lesson_plans_select" ON lesson_plans FOR SELECT
  USING (
    teacher_id = auth.uid()
    OR current_role_name() = 'director'
    OR (status = 'approved' AND EXISTS (
      SELECT 1 FROM classes c WHERE c.id = lesson_plans.class_id AND auth.uid() = ANY(c.teacher_uids)
    ))
    OR (status = 'approved' AND EXISTS (
      SELECT 1 FROM children ch
      JOIN children_parents cp ON cp.child_id = ch.id
      WHERE ch.class_id = lesson_plans.class_id AND cp.parent_id = auth.uid()
    ))
  );
-- §6.5: the subject LABEL of a class's approved plans, for showing the
-- subject on schedule events to EVERY role (incl. parents who can't read the
-- lesson_plans rows directly). Returns only plan id + title + subject (no
-- content) to a viewer connected to the class. Used on the agenda cards AND
-- the day view. SECURITY DEFINER so the connection check gates every row.
CREATE OR REPLACE FUNCTION class_plan_subjects(p_class_id UUID)
RETURNS TABLE (plan_id UUID, title TEXT, subject_name TEXT)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT lp.id, lp.title, s.name
  FROM lesson_plans lp
  LEFT JOIN subjects s ON s.id = lp.subject_id
  WHERE lp.class_id = p_class_id
    AND lp.status = 'approved'
    AND (
      current_role_name() = 'director'
      OR EXISTS (SELECT 1 FROM classes c WHERE c.id = p_class_id AND auth.uid() = ANY(c.teacher_uids))
      OR EXISTS (
        SELECT 1 FROM children ch
        JOIN children_parents cp ON cp.child_id = ch.id
        WHERE ch.class_id = p_class_id AND cp.parent_id = auth.uid()
      )
    );
$$;

CREATE POLICY "lesson_plans_insert" ON lesson_plans FOR INSERT
  WITH CHECK (current_role_name() = 'teacher' AND teacher_id = auth.uid());
CREATE POLICY "lesson_plans_update_teacher" ON lesson_plans FOR UPDATE
  USING (current_role_name() = 'teacher' AND teacher_id = auth.uid())
  WITH CHECK (
    current_role_name() = 'teacher'
    AND teacher_id = auth.uid()
    AND status IN ('draft', 'submitted')
  );
CREATE POLICY "lesson_plans_update_director" ON lesson_plans FOR UPDATE
  USING (current_role_name() = 'director')
  WITH CHECK (current_role_name() = 'director');
CREATE POLICY "lesson_plans_delete" ON lesson_plans FOR DELETE
  USING (current_role_name() = 'director' OR teacher_id = auth.uid());

-- Director-only cascading deletes done as SECURITY DEFINER functions (so they
-- can clear dependent rows across tables without a delete policy on each),
-- each gated on the caller being a director. Used by the long-press Delete on
-- the People > Classes / Children lists.
CREATE OR REPLACE FUNCTION delete_class(p_class_id UUID) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF current_role_name() <> 'director' THEN RAISE EXCEPTION 'not authorized'; END IF;
  UPDATE children SET class_id = NULL WHERE class_id = p_class_id;        -- un-assign children
  UPDATE lesson_plans SET class_id = NULL WHERE class_id = p_class_id;    -- detach plans
  DELETE FROM schedule_entries WHERE type = 'class' AND ref_id = p_class_id;  -- its schedule
  DELETE FROM classes WHERE id = p_class_id;
END;
$$;

CREATE OR REPLACE FUNCTION delete_child(p_child_id UUID) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF current_role_name() <> 'director' THEN RAISE EXCEPTION 'not authorized'; END IF;
  DELETE FROM children_parents WHERE child_id = p_child_id;
  DELETE FROM attendance WHERE child_id = p_child_id;
  DELETE FROM daily_reports WHERE child_id = p_child_id;
  DELETE FROM schedule_entries WHERE type = 'child' AND ref_id = p_child_id;
  DELETE FROM children WHERE id = p_child_id;  -- storage photos are left orphaned (deferred cleanup)
END;
$$;

-- daily_reports: teachers write; parents read their child's
CREATE POLICY "daily_reports_select" ON daily_reports FOR SELECT
  USING (
    teacher_id = auth.uid()
    OR current_role_name() = 'director'
    OR EXISTS (SELECT 1 FROM children_parents WHERE child_id = daily_reports.child_id AND parent_id = auth.uid())
  );
-- SECURITY HARDENING (M3): a teacher may only write a daily report for a child
-- in their own class -- not any child in the DB.
CREATE POLICY "daily_reports_insert" ON daily_reports FOR INSERT
  WITH CHECK (
    current_role_name() = 'teacher'
    AND EXISTS (SELECT 1 FROM children
                WHERE children.id = daily_reports.child_id AND children.teacher_id = auth.uid())
  );
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
              ├── TeacherShell     → BottomNav: Schedule | Attendance | Lessons | Reports | Profile (opens on Lessons)
              └── DirectorShell   → BottomNav: Teachers | Schedules | Lesson Plans | Attendance
```

### Folder structure

Actual structure as of this writing — `(not yet built)` marks planned files that don't exist yet:

```
lib/
  main.dart                         -- checks the SUPABASE_URL / SUPABASE_ANON_KEY --dart-defines first; if either is empty it shows MissingConfigApp instead of a login that can never work
  core/
    app_config.dart                 -- missingSupabaseDefines() + MissingConfigApp (2026-10-21)
    auth/
      auth_gate.dart
      auth_controller.dart
      sign_in_error_message.dart    -- maps sign-in errors to login text: only rejected credentials say "Invalid email or password"; network failures say "Can't reach the server..." (kServerUnreachableMessage, reused by the error view) (2026-10-21)
      role_router.dart
    constants/
      schedule_colors.dart          -- shared color palette (picker + display)
    models/
      app_user.dart
      child.dart
      attendance.dart
      schedule.dart                 -- ScheduleEntry: one row per event, not a whole-week blob
      lesson_plan.dart              -- LessonPlan + LessonPlanStatus enum (§6.5)
      subject.dart                  -- center-defined lesson subject/category (§6.5)
      daily_report.dart
      class_group.dart              -- the `classes` table (named ClassGroup; `Class` is reserved) (§6.8)
    controllers/                    -- the app's "controller" layer: logic + Supabase access (formerly `services/`)
      child_controller.dart
      teacher_controller.dart
      class_controller.dart            -- fetch classes + resolve a class's teacher (§6.8)
      schedule_controller.dart
      attendance_controller.dart
      photo_capture_controller.dart    -- thin ImagePicker wrapper, injectable/mockable
      user_management_controller.dart  -- calls the create-user Edge Function (invite teacher/parent)
      profile_controller.dart          -- user avatar upload/signed-url + set/update RPCs + director edit (§6.7)
      daily_report_controller.dart     -- fetch/save reports + report-image upload/signed-url (§6.4)
      lesson_plan_controller.dart      -- lesson plan CRUD + submit/review (approval) (§6.5)
      subject_controller.dart          -- center subjects CRUD (§6.5)
    theme/
      app_theme.dart                -- white base surface, soft pink (`#FDB0C0`) as the accent (`colorScheme.primary`, `onPrimary` = dark rose `#5A2A33`); bars carry a faint pink wash (`AppTheme.barTint`); bottom-nav selection pill and attendance headers are the pink accent; role chips get a soft-pink tint via `chipTheme`; font (Nunito via google_fonts) cascades app-wide (see §2026-09-07-theme-pink-on-white-design.md)
  features/
    auth/
      login_screen.dart             -- includes "Forgot password?" -> ForgotPasswordScreen
      set_password_screen.dart      -- invite completion + password recovery (§6.6a / §6.7a)
      forgot_password_screen.dart   -- sends the recovery email (§6.7a)
    profile/
      profile_screen.dart           -- shared account settings tab, all roles (§6.7)
      change_password_screen.dart   -- change password while signed in (§6.7)
      person_detail_screen.dart     -- view/edit a person's name/phone/photo; self or director-edits-other (§6.6/§6.7)
      staff_attendance_screen.dart  -- teacher's own clock-in/clock-out for today, reached from Profile (§6.7)
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
        teacher_lesson_plans_screen.dart -- teacher's own lesson plans list + create (§6.5). Screen design A1 (Figma page "Screen designs"): greeting, summary cards (total / need attention = draft+rejected / approved), cards with SubjectTile + "subject · class" + status + reviewer feedback strip, pinned "Create lesson plan" button. No dates: lesson plans have no date column (2026-10-21)
    director/
      director_shell.dart
      screens/
        director_attendance_screen.dart
        director_schedules_screen.dart  -- searchable class list -> PersonScheduleScreen (type='class') (§6.8)
        person_schedule_screen.dart     -- reusable editable agenda view for any teacher/child/class
        people_screen.dart              -- Teachers | Children | Classes sub-tabs (§6.6)
        manage_teachers_screen.dart     -- teacher list (tap -> PersonDetailScreen) + invite-a-teacher
        manage_children_screen.dart     -- child list (tap -> ChildDetailScreen) + invite-a-parent
        manage_classes_screen.dart      -- class list (tap -> ClassDetailScreen) + create-a-class dialog (§6.8)
        class_detail_screen.dart        -- director view/edit of one class: photo, name, teacher (§6.8)
        enroll_child_screen.dart        -- child record + first parent invite in one form
        child_detail_screen.dart        -- director view/edit of one child + parent contacts (§6.6)
        director_lessons_screen.dart    -- browse/filter all lesson plans, approve/reject (§6.5)
        manage_subjects_screen.dart     -- director-managed subjects list (§6.5)
    shared_lessons/
      lesson_plan_edit_screen.dart      -- shared teacher/director lesson-plan editor + submit/review/delete (§6.5). Screen design A2: status chip + Delete in the app bar, reviewer feedback banner, BASICS/CONTENT sections with labels above white thin-bordered fields (AppTheme.lightForm, scoped to this screen), Subject|Class side by side, actions pinned in a bottom bar (2026-10-21)
      lesson_plan_view_screen.dart      -- read-only plan (subject/title/content), opened from a schedule event (§6.5)
  shared/
    util/
      date_display.dart             -- weekdayName + isoWithWeekday: prefix an ISO date with its weekday (attendance/report displays; not birthdates)
    screens/
    widgets/
      logout_button.dart
      app_bottom_nav.dart           -- floating (inset + rounded) bottom bar used by every shell. Unselected tabs are icon-only; the selected tab grows to [icon][label], its label sliding out from behind the icon as the pink pill slides + stretches over (2026-10-21)
      app_icon.dart                 -- AppIcon(AppIcons.x, filled:) draws the brand icons (assets/icons/<name>_outline|filled.svg). Source is the v1 set on Figma page "Brand & Icons" (thin 2px-on-48px strokes), plus filled variants built there for selected tabs. 8 icons: people, schedule, lessons, attendance, reports, profile, notifications, offline. Tinted from IconTheme like Icon. Used by every shell tab (outline unselected, filled selected) and the AppBar notification bell. A bolder v2 set was tried and dropped (2026-10-21)
      lazy_indexed_stack.dart       -- shell tab bodies: a page is built on its first visit, then kept alive (hidden). Replaced `body: _pages[_index]`, which rebuilt the page + re-ran its initState fetch on every tap and stalled the nav animation (2026-10-21)
      refreshable_message.dart      -- centred empty-state text that can still be pulled to refresh. Kept-alive tab pages that load once in initState (DirectorAttendance, DirectorLessons, MarkAttendance, TeacherLessonPlans, TeacherReports) all have pull-to-refresh, since revisiting a tab no longer refetches
      row_actions_sheet.dart        -- long-press Edit/Delete bottom sheet + confirmDelete (§6.6)
      attendance_status_chip.dart
      lesson_plan_status_chip.dart  -- dot-pill status chip with semantic colours (grey/amber/green/red); `rejected` is labelled "Needs changes"; colorsFor()/labelFor() shared with feedback strips (§6.5)
      subject_tile.dart             -- subject initials on a pastel picked by a stable hash of the name (subjects are free text, so no per-subject art); book icon when none
      signed_photo_thumbnail.dart   -- exchanges a private Storage path for a signed URL, with loading/error states
      signed_avatar.dart            -- round avatar from any bucket's signed-URL provider, with placeholder (§6.6/§6.7)
      avatar_source_sheet.dart      -- shared take-photo/gallery bottom sheet for avatar edits
      person_invite_dialog.dart     -- shared name/email/phone dialog for teacher & parent invites
      class_form_dialog.dart        -- shared create/edit-a-class dialog (name + teacher dropdown) (§6.8)
      editable_field.dart           -- read-only row / fading text input toggle + tap-to-copy (§6.6c)
      avatar_preview.dart           -- tappable avatar -> full-screen zoomable photo (§6.6c)
      schedule_agenda_view.dart     -- the whole Schedule tab: month header (Today, date picker), week strip, List|Timeline toggle (agenda cards or DayTimetable), now line; owns create/edit/delete via the event sheet
      day_timetable.dart            -- hour grid (SA2 look: pale blocks + colour bar, nowTime fades past events + now line), tap-to-add/edit, fade-in on new entries
      week_strip.dart               -- Mon-Sun day picker with event dots, swipe = week (agenda + day view)
      schedule_event_sheet.dart     -- one bottom sheet to view (summary), edit (Edit swaps in the form) and create an event: name, start/end, Once|Daily|Weekly picker, lesson plan, colour; delete confirmed
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
Schedule entries now repeat **once**, **daily** (weekdays), or **weekly** — a `recurrence` column plus an optional `anchor_date` on `schedule_entries` (see `docs/superpowers/specs/2026-09-07-schedule-recurrence-design.md`). The occurrence rule is `scheduleEntryOccursOn`, and `day` still drives weekly entries. Each event shows up on matching dates, not a one-off.

- Schedules are **class-owned** (`type='class'`, `ref_id = class_id`) — §6.8, so a class's schedule is independent of how many teachers it has.
- **Director**: Schedules tab is a searchable **class** list → lands on that class's editable agenda/day view (tap a day for the hourly timetable, tap a slot / **+** to add, tap an event to edit/delete).
- **Teacher**: manages the schedule of the class they're assigned to (`ClassController.fetchForTeacher`), same editable view.
- **Parent**: read-only view of their child's class schedule (child → `class_id` → `type='class'` entries); falls back to "Not assigned to a class yet".
- **Edit/delete permission on a specific event**: only the person who created it, or any director — enforced by `schedule_entries` RLS, not just the UI (see §4).
- **Display**: week/month toggle agenda view (colored event cards, "No events" for empty days) + a per-day hourly timetable when you tap into a day. Each event has a color, chosen from a fixed palette at creation, saved to the database, and shown identically everywhere it appears.

### 6.3 Attendance
Teacher marks attendance via a grid of tiles (see `docs/superpowers/specs/2026-09-01-teacher-attendance-grid-design.md` for full design). The teacher's **Attendance** tab displays two grids divided by labelled separators (see `docs/superpowers/specs/2026-09-07-teacher-attendance-two-grids-design.md` for the two-grid layout):

**Teachers grid:** The signed-in teacher's own tile appears first with a **three-state clock-in/out badge** (not clocked in / working / done), tapping it opens the clock screen (`StaffAttendanceScreen`). Co-teachers assigned to the teacher's class(es) appear below with no badge; tapping a co-teacher's tile opens their profile in read-only mode (no Edit button, HR fields hidden). The clock-in/out entry point moved from the Profile tab to this grid. The teacher-only gating is that the Teachers grid exists only on the teacher attendance screen.

**Children grid:** Unchanged — tiles, search, mark present/absent, empty states, and photos work as described below.

- Grid displays children as square avatar tiles in rows, each showing a status badge (green check = present, red X = absent, amber question = unmarked)
- Each tile displays a shortened name label (`shortLabelName`: first word + last initial, e.g. "Ammar H.") on a single line, keeping avatars uniformly sized regardless of name length
- **Tap** a tile to open the detail screen for that child (photo slots, status buttons, notes, expandable child details)
- **Long-press** a tile for a quick menu: Open details, Mark present, Mark absent (short-cut for common case)
- Search bar filters the grid by name
- One record per child per day — re-opening the screen shows existing marks for editing
- Status taps and photo captures update the UI from the write's returned row instead of re-fetching the whole roster (same round-trip-avoidance as `ScheduleController`'s create/update)
- Once a status is set, the teacher can optionally take a check-in photo and/or a photo of the child's belongings/clothes for the day — both are entirely optional, unrelated to status, and independent of each other. One photo of each kind per child per day
- Signed URLs are cached per photo path in a Riverpod `FutureProvider.family` for the app's session, so repeated access reuses the already-fetched URL instead of re-hitting Storage
- Both photos are visible to parents (child's attendance history) and directors (attendance tab), fetched via a signed URL since the Storage bucket is private
- Director can filter and view attendance across all children and dates

### 6.4 Daily Reports — built (teacher write, parent read)
- **Teacher** (Reports tab, `TeacherReportsScreen`): their class as a list; tap a child → `DailyReportEditScreen` to write today's report — free text + photos. One report per child per day, so it opens the existing one to edit or a blank form. Photos upload immediately to the `daily-report-images` bucket; text + image paths persist on Save (via `DailyReportController.saveReport`, insert-or-update on the child+date row).
- **Parent** (Reports tab, `ChildReportsScreen`): for each linked child, a read-only feed of daily reports newest-first — the teacher's note + photo thumbnails (signed URLs).
- **Director**: reads all via RLS, but no dedicated reports screen yet (⬜ could add a browse view later).
- Data: `daily_reports` table (one row per child+date), image paths stored on the row, photos in the private `daily-report-images` bucket.

### 6.5 Lesson Plans — built (Increment 1 of the "full vision")
Teacher-authored plans with a **subject** categorization and a **director approval workflow**. Visible to teachers + directors only (not parents).
- **Subjects** — a center-defined list (`subjects` table) the director manages (`ManageSubjectsScreen`, reached from the director Lessons tab). Teachers tag a plan with one. Any authenticated user can read subjects (they'll surface on the schedule in a later increment); only directors write them.
- **Teacher** (`TeacherLessonPlansScreen`, Lessons tab): lists own plans (newest first) with a status chip; **+** writes a new one. `LessonPlanEditScreen`: title, date, subject, optional class, content. Editable while **draft/rejected**; **Submit** flips it to *submitted* (then read-only to the teacher); Delete (own).
- **Director** (`DirectorLessonsScreen`, Lessons tab): browses **all** plans, filters by teacher + status, opens one to **Approve / Reject** (with an optional note) and can edit/delete any.
- **Editor layout (2026-10-04):** Delete sits at the right end of the status-chip row (theme error colour), away from the main actions; Approve is a plain `FilledButton` in the theme's primary colour (was hard-coded green), Reject an `OutlinedButton` beside it.
- **Approval states:** `draft → submitted → approved | rejected` (`LessonPlanStatus`). A rejected plan shows the reviewer's note and becomes editable again.
- **Security (enforced at the DB, not just UI):** two UPDATE policies — a teacher may only set `draft`/`submitted` on their **own** plan (so a teacher **cannot self-approve**); a director may set any status on any plan. See §4 RLS.
- ✅ **Increment 2 — attach a lesson plan to a schedule event (reshaped):** lesson plans are **reusable** — the `date` column was dropped; a plan is now subject + title + content + class + status, made once and attached to schedule events. When creating/editing a **class** event (the event sheet, `schedule_event_sheet.dart`; was `ScheduleEntryFormDialog`), a **Lesson plan** picker lists that class's **approved** plans (`schedule_entries.lesson_plan_id`). The event then shows the attached plan's **subject** on the timetable; **tapping the event, then its plan card, opens the plan read-only** (`LessonPlanViewScreen`, incl. content). This replaced the earlier day-view "Planned lessons" section + the `class_day_lessons` function (both removed).
  - **Visibility:** `lesson_plans_select` was widened so a **connected role** (the class's teacher, or a parent of a child in the class) can read **approved** plans — so tapping a scheduled subject opens the full plan for parents too, while drafts/unapproved stay teacher/director-only. See §4 RLS.
  - **Subject on events (every role):** the subject **label** shown on schedule event cards — on both the weekly/monthly **agenda** and the **day view** — is resolved via the **`class_plan_subjects(class_id)` SECURITY DEFINER function** (§4), which returns just each approved plan's id+title+subject to a connected viewer. This is what makes the subject appear for **parents** (who can't read `lesson_plans` rows), independent of the widened SELECT above (that one only governs opening the full plan's content).
  - 🔭 Content is plain text fields for now; a richer format (e.g. PDF attachments) is a possible later upgrade.
- ✅ **Increment 3 — notifications for approval events:** a generic
  `notifications` table (`type`/`status`/`title`/`body`/`entity_id`, RLS
  scoped to `user_id = auth.uid()`) is populated by a `SECURITY DEFINER`
  trigger (`lesson_plan_status_notify`) on `lesson_plans` status changes: a
  `submitted` plan notifies every director in the plan's own `center_id`; an
  `approved`/`rejected` plan notifies its author, including the review note
  on rejection. Surfaced in-app via Supabase Realtime (`AppNotification`,
  `NotificationController.watchNotifications`, `notificationsProvider`) as a
  bell icon + unread badge (`NotificationBellAction`) in both `TeacherShell`
  and `DirectorShell`, leading to `NotificationsScreen` — tapping a row opens
  `LessonPlanEditScreen` for that plan. No dashboard (a separate, larger
  piece of work) and no push/email — see
  `docs/superpowers/specs/2026-09-15-lesson-plan-notifications-design.md`.

### 6.6 Director / Admin Panel — partially built
- ✅ View all attendance records, any date (Attendance tab)
- ✅ View/edit any teacher's or child's schedule (Schedules tab, §6.2)
- ✅ **People tab** (Teachers | Children | Classes sub-tabs) for account provisioning:
  - Invite a teacher by email
  - Enroll a child and invite its first parent in one form; invite additional parents per child from the Children list
- ✅ **Tap a row to view/edit details:**
  - A child → `ChildDetailScreen`: edit photo (child-avatars bucket), name, date of birth (age is shown, derived), **class** (a dropdown of real `classes` rows setting `class_id` — helper text "Drives the schedule the parent sees"; replaced the old free-text `class_name` field, which is now preserved untouched), class teacher (dropdown, sets `teacher_id`), allergies, notes — saved via `ChildController.updateChild` (director-only per `children_update` RLS). Also shows a read-only **Parents** section (each linked parent's name + email, via `ChildController.fetchParentsForChild`).
  - A teacher/parent → `PersonDetailScreen`: edit photo, name, phone, and **HR/contact details** (address, date of birth, emergency contact name/phone — §6.6b), plus a **read-only login email**. A director editing someone else uses `updatePersonDetails` + `setAvatarPathFor` (director policy); editing yourself uses the self-only `update_own_profile` / `setAvatarPath` RPCs (see §6.7).
- ✅ **Delete records via long-press:** on the People (Classes, Children), and the Lessons (teacher + director) and Subjects lists, **long-pressing a row** opens a bottom-sheet with **Edit / Delete** (`showRowActionsSheet`; Delete asks `confirmDelete` first). Deleting a **class** (`delete_class`) un-assigns its children/plans + clears its schedule; deleting a **child** (`delete_child`) removes its parent links, attendance, and daily reports — both are director-only SECURITY DEFINER functions (§4). Lesson plans / subjects delete via their own service calls.
- ⬜ Deactivate/delete **accounts** (teacher/parent) still needs an Edge Function (auth.users deletion is server-side) — not built; the long-press menu isn't offered on the Teachers list yet.
- ⬜ View all lesson plans across the center (depends on §6.5)
- ⬜ Manage center settings (center name, rooms)

**How account provisioning works (§6.6a):** The Flutter app can never create accounts for other people directly — that needs Supabase's admin API and the service role key, which must stay server-side. So a director's invite calls the **`create-user` Edge Function** (`supabase/functions/create-user`): it verifies the caller is a director via their own JWT, then uses the service role key to `inviteUserByEmail` and insert the `profiles` row (with `must_set_password = true`). The invite email's link opens the **web set-password page** at `https://kids.akmalcodes.quest/` (static site on Cloudflare Pages; see the 2026-08-24 design spec). It carries `?token_hash=…&type=invite`, and the page exchanges that for a session only when the form is submitted — linking straight at `/auth/v1/verify` was abandoned because that GET consumes the single-use token, and mail scanners prefetching it burned links before recipients clicked. A custom URL scheme was used originally and removed entirely: it dead-ends on every desktop click and on any phone without the app installed. The page clears `must_set_password` via the same `complete_password_setup()` RPC the app used to. On first entry the invited user lands on `SetPasswordScreen` (routed by `AuthGate` when `must_set_password`), sets a password, and the flag is cleared via the `complete_password_setup()` SECURITY DEFINER RPC (avoids granting a broad `profiles` UPDATE policy that could let users change their own role).

> ⚠️ **Production requirement — custom SMTP not yet configured.** Invite and password-recovery emails currently go through Supabase's built-in email sender, which is a shared, heavily rate-limited service intended only for development (hitting "email rate limit exceeded" after a few test invites is expected). Before inviting real teachers/parents, a custom SMTP provider (e.g. Resend, SendGrid) **must** be configured in Dashboard → Project Settings → Authentication → SMTP Settings. Supabase generates the invite/recovery link and its token; the SMTP provider is what actually delivers the email reliably to real inboxes (analogous to why production PHP uses PHPMailer + a real mail service instead of the built-in `mail()`).

**Detail screens — view-then-edit (§6.6c — built):** the three detail screens (`ChildDetailScreen`, `ClassDetailScreen`, `PersonDetailScreen`) open **read-only**: values render as labelled text, and there's no Save button. An **edit (✏️) icon** in the AppBar flips the screen into edit mode — the inputs **cross-fade in** (shared `EditableField` via `AnimatedSwitcher`), the icon becomes a **close (✕)** that **cancels** (restores every field from the last-saved values and returns to read-only; Save is what persists), and "Change photo" + the Save button appear. **Email and phone rows copy to the clipboard when tapped** in read-only view (child screen: the linked parents' emails). The **avatar is tappable** to open a full-screen, pinch-zoomable preview (shared `AvatarWithPreview`), social-app style. Save behaviour is unchanged (persists via the same service call, pops the updated record so the list refreshes) — so the last-saved baseline for cancel is always the record the screen was opened with.

**HR / contact details (§6.6b — built):** every profile carries optional HR fields — `address`, `dob`, `emergency_contact_name`, `emergency_contact_phone` — editable on `PersonDetailScreen` by the person themselves (self path, `update_own_profile`) or a director (director path, `updatePersonDetails`). Same fields for all roles. The **login email is shown read-only** — it's the auth identity, not editable here; `profiles.email` is kept equal to `auth.users.email` by the `sync_profile_email` trigger (+ a one-time backfill), so the parent-contacts list on `ChildDetailScreen` and the email row here are always correct rather than depending on the invite-time copy.

### 6.7 Profile / Account settings — all roles
Every role has a **Profile** tab (shared `ProfileScreen`) showing their avatar, name, email (read from the auth session, not the profiles row), and role, with actions to:
- **Change photo** — take or pick a photo, uploaded to the private `avatars` bucket; the path is saved via the `set_avatar_path()` RPC and displayed through a signed URL.
- **Profile details** — opens the shared `PersonDetailScreen` for the current user, to edit name/phone/photo (self-edit path: `update_own_profile` / `setAvatarPath`). The same screen is reused by the director's People tab for editing others.
- **Change password** — `ChangePasswordScreen` (already signed in, so just captures a new password via `updateUser`; distinct from the invite/recovery `SetPasswordScreen` because it pops back on success instead of relying on `AuthGate` to re-route).
- **Sign out**.

**Forgot password (§6.7a):** `LoginScreen` has a "Forgot password?" link → `ForgotPasswordScreen`, which calls `resetPasswordForEmail` with `redirectTo: https://kids.akmalcodes.quest/`. The recovery email is sent by Supabase's mailer over Mailgun SMTP using the "Reset password" dashboard template (mirrored in `docs/email-templates/reset-password.html`), and its link opens the web page — the same one invites use. The user sets the password in the browser and then signs in normally; **the flow no longer re-enters the app**, so the in-app recovery path (`passwordRecoveryProvider` → `AuthGate` recovery mode) is now dormant rather than load-bearing. It is left in place because it costs nothing and would be needed again if App Links are ever adopted.

### 6.8 Classes — partially built (schema + parent-schedule link)
A `classes` table groups children under an assigned teacher, added **additively** alongside the existing `children.teacher_id` (see the `classes` schema note in §4 for the reasoning).
- ✅ Schema: `classes` (id, name, teacher_uids, center_id, avatar_path) + `children.class_id` + RLS (directors manage; teachers see own; parents see their child's class).
- ✅ **Class-owned schedules** (`type='class'`, `ref_id=class_id`): director edits per class (Schedules tab = class list), teacher edits their assigned class's schedule, parent reads their child's class schedule. Chosen over teacher-owned so multiple teachers per class (future) has one schedule. Old `type='teacher'` entries are orphaned. Each entry repeats once, daily (weekdays), or weekly via the `recurrence` and `anchor_date` columns (see §6.2 and `2026-09-07-schedule-recurrence-design.md`).
- ✅ **Class-management UI** (People tab → **Classes** sub-tab, `ManageClassesScreen`): director lists classes (avatar + assigned teacher's name), and creates a class via the shared `showClassFormDialog` (name + teacher dropdown). **Tapping a class opens `ClassDetailScreen`** (a full screen like children/teachers, not a dialog): edit the **class photo** (class-avatars bucket), name, and teacher, via `ClassController.updateClass` / `uploadClassAvatar` / `setClassAvatarPath`. Create stays a dialog because there's no `class_id` to key the photo path until the row exists — add a picture by opening the new class afterwards. Assigning **children** to a class stays on `ChildDetailScreen` (the class dropdown). This removes the SQL-only step for classes.
- ✅ **Deleting a class** is built (long-press a class → Delete, via the `delete_class` function, §6.6). Undecided: whether `class_id` should ultimately supersede `teacher_id` / `class_name` (kept redundant for now — `teacher_id` still drives attendance/daily-report RLS).
- ✅ **Done (2026-09-04) — multiple teachers per class:** implemented via `classes.teacher_uids UUID[]` (array column) rather than a `class_teachers` junction — array-membership RLS scales smoothly to any teacher count. `children.teacher_id` remains unchanged and separate, as designed (see §6.8 and 2026-09-04-co-teachers-design.md).
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
| 7 | Lesson Plans — Increment 1 (subjects + CRUD + approval) + Increment 2 (reusable plans attached to schedule events; subject shown on the event, tap opens the plan) + Increment 3 (notifications for approval events) | ✅ Done. A dashboard view was scoped out of Increment 3 — not yet built |
| 8 | Play Store release prep (see §11) | ⬜ Not started |
| 9 | Web build + polish | ⬜ Not started |

## 11. Play Store release prep (not started)

Tracked for later; none of this is code-complete yet. Blocking items are called out.

- ✅ **Rename `applicationId`**: done on 2026-10-20 as part of the rename to **KawanKecil**. Android applicationId/namespace and the iOS bundle id are `com.akmalcodes.kawankecil`; the Dart package is `kawankecil`. Google Play rejects `com.example`, which is why the placeholder had to go. Auth doesn't depend on the id: email links point at `https://kids.akmalcodes.quest/`.
- ✅ **Display name** is **KawanKecil** (Malay for "little friend"). It's used for the launcher label (Android `android:label`, iOS `CFBundleDisplayName`), the login title, the role-shell app bars, `MaterialApp.title`, the web set-password page and the email templates.
- ✅ **Launcher icon + brand** (Android + iOS) is done. Since 2026-10-21 the logo is the **"Kids house"** mark from the brand board (Figma file "KawanKecil — Brand & Icons", https://www.figma.com/design/5O0Y0SX0MkjtKuttKmr6JR, page "KawanKecil Brand v2"; a simplified redraw of a ChatGPT-suggested board kept at `docs/KawanKecil Kids App Brand Board.png`). It shows a house roof sheltering a teacher (hair bun, heart on chest) with a boy and girl cheek-to-cheek in front. It replaced logo D1 "Family in the blocks", which is still on the older Figma page. The board holds the lockups (P1 primary, L1–L3), four app-icon options (I1–I4), and the colour styles, including two new ones: Accent pink `#F2849E` (the "Kawan" in the wordmark, the teacher's body) and Skin `#FFE4E6`. **App icon = I1 on a white background.** Two 1024px PNGs are exported from the frames `export/app-icon v2 (I1, white)` and `export/adaptive-foreground v2` into `assets/icon/`. `flutter_launcher_icons` (config in `flutter_launcher_icons.yaml`) generates every platform size from them. Android uses an adaptive icon: white `#FFFFFF` background plus the transparent foreground, with the mark padded inside the 66/108 safe zone in Figma, so `adaptive_icon_foreground_inset: 0`. Re-run steps and two gotchas (don't generate for `web/`; revert the generator's `project.pbxproj` edit) are commented in that YAML. **In-app logo = lockup P1, stacked for portrait.** The LoginScreen shows the mark (`AppLogo`, `assets/logo/app_logo.svg`), the wordmark (`AppWordmark`, `assets/logo/app_wordmark.svg`: Fredoka lettering exported as outlined paths, so no font is bundled, with a heart dotting the "i") and the tagline "Teman Tumbesaran Si Kecil." as a Nunito `Text` in dark rose. Both SVGs render via `flutter_svg`. The board's side-by-side P1 is too wide for a phone screen.
- **Play App Signing**: create an upload keystore (`keytool`), keep the keystore + passwords backed up outside the repo, wire a release signing config.
- Build: `flutter build appbundle --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...` (anon key is safe to ship; RLS protects the data).
- Play Console listing: store listing assets, content rating, **Data safety form + privacy policy URL** (we store emails and children's photos), target-audience = adults (users are teachers/parents/directors).
- Distribution: **Internal testing track** is the portfolio path (shareable install link, minimal review). A full production launch of a real childcare app carries children's-data privacy weight (COPPA/GDPR-K) — use dummy data for the portfolio demo.
- New personal developer accounts must run a closed test with a minimum number of testers (~12) for 14 days before production access (doesn't affect internal testing).

---

## 12. Security audit (2026-08-07)

Findings from a defensive review of the RLS policies, SECURITY DEFINER functions, the `create-user` Edge Function, auth/deep-link handling, and secret injection. **Good baseline:** no hardcoded secrets (service-role key server-only; anon key is public-safe), parameterized queries throughout (no SQL injection), RLS on every table, private buckets + signed URLs, and the teacher-can't-self-approve split policy.

**Fixed (code + docs in this repo; SQL in [`2026-08-07-security-hardening.sql`](2026-08-07-security-hardening.sql), run once in Supabase):**
- **M2** — `profiles` column-level UPDATE lockdown so clients can't change `role`/`center_id`/`email`/`must_set_password` (privilege-escalation guard). Legitimate edits go through the granted columns or the SECURITY DEFINER RPCs.
- **M3** — `attendance_insert` / `daily_reports_insert` now require the child to be in the teacher's class (a teacher couldn't otherwise be stopped from writing for any child).
- **M4** — every SECURITY DEFINER function pins `SET search_path = ''` + schema-qualifies (search-path-hijack guard); the cascading deletes (`delete_class`/`delete_child`) also gained a **center guard**.
- **M5** — the `create-user` Edge Function verifies a parent-link `childId` belongs to the caller's own center before linking (the admin client bypasses RLS). **Redeploy the function** after pulling.
- **M1** — multi-center isolation: every "director sees/edits all" policy is now scoped `AND center_id = my_center()` (new `my_center()` helper), plus explicit **`classes`** policies (previously undocumented) and **storage** policies for `avatars` / `child-avatars` / `class-avatars` / `daily-report-images` (**L2** — only `attendance-photos` had been written out).

**Bug found after M1 shipped, fixed 2026-08-11** (SQL folded into [`2026-08-07-security-hardening.sql`](2026-08-07-security-hardening.sql) — re-run that file, it's idempotent): M1's `children_parents` director clause added `EXISTS (SELECT 1 FROM children ...)` to scope by center. That subquery runs under `children`'s own RLS, which queries `children_parents` back, which re-triggers its own RLS, which queries `children` again — infinite recursion. Postgres throws `infinite recursion detected in policy for relation "children"`; symptoms were an immediate error on the lessons tab and a stuck spinner on schedule/attendance (same cycle, different call sites). Fixed with a new SECURITY DEFINER helper `child_center(child_id)` that reads the center without going through RLS, same pattern as `my_center()`.

**Still open (deliberate):**
- **H1 — RESOLVED (2026-09-01).** Was: the auth deep link used an unverified custom URL scheme (`com.example.kidsmanagement://`), which any app could register to intercept an invite/recovery token → account takeover. **Retired by deletion, not by verification** — auth emails now open an https page, and the scheme registration was removed from `AndroidManifest.xml` and `ios/Runner/Info.plist` and from the Supabase redirect allow-list, so there is nothing left to hijack. Android App Links / iOS Universal Links remain available later as a UX improvement (opening the app directly from the same URL), but are no longer a security fix.
- **L1** — the `create-user` Edge Function has no CORS handling (needed for a Flutter **web** build) and no invite throttling/input-length caps.
- **L3 — RESOLVED.** Invite email deliverability. Was: sent via a `sendInviteEmail` helper in `create-user` using Mailgun's free sandbox domain, which can never pass DMARC alignment, so invites landed in Gmail spam and only reached manually authorized recipients. Now: a real verified sending domain (`mg.akmalcodes.quest`, see `docs/mailgun-porkbun-domain-setup.md`), reached through Supabase's mailer over Mailgun SMTP. `sendInviteEmail` and the Mailgun HTTP API path were deleted; invites and password recovery now share one sending path and are styled in the dashboard templates.
