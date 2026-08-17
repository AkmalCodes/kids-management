-- =====================================================================
-- Security hardening — run once in the Supabase SQL Editor.
-- Idempotent: safe to re-run (DROP POLICY IF EXISTS + CREATE OR REPLACE).
--
-- Covers the 2026-08-07 security audit:
--   M2  profiles column lockdown              (also in the earlier handoff)
--   M3  attendance/daily-report insert scope  (also in the earlier handoff)
--   M4  SECURITY DEFINER search_path pinning   + center guards on deletes
--   M1  multi-center isolation (directors only see/edit their own center)
--   L2  explicit RLS for the avatars / child-avatars / class-avatars /
--       daily-report-images storage buckets
-- (M5 is the create-user Edge Function — deploy it separately.)
-- =====================================================================

-- Helper: the caller's own center. SECURITY DEFINER so it can read profiles
-- regardless of RLS; search_path pinned (M4).
CREATE OR REPLACE FUNCTION my_center() RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT center_id FROM public.profiles WHERE id = auth.uid();
$$;

-- current_role_name already exists; ensure it's hardened (M4).
CREATE OR REPLACE FUNCTION current_role_name() RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid();
$$;

-- ---------------------------------------------------------------------
-- M2 — profiles: clients may only UPDATE the editable columns (never
-- role/center_id/email/must_set_password). SECURITY DEFINER RPCs + the
-- service_role bypass column grants, so legitimate flows keep working.
-- ---------------------------------------------------------------------
REVOKE UPDATE ON public.profiles FROM authenticated;
GRANT UPDATE (name, phone, address, dob, emergency_contact_name,
              emergency_contact_phone, avatar_path, updated_by, updated_at)
  ON public.profiles TO authenticated;

-- ---------------------------------------------------------------------
-- M1 — director clauses scoped to the caller's own center.
-- ---------------------------------------------------------------------

-- profiles
DROP POLICY IF EXISTS "profiles_select" ON profiles;
CREATE POLICY "profiles_select" ON profiles FOR SELECT USING (
  id = auth.uid()
  OR (current_role_name() = 'director' AND center_id = my_center())
);
DROP POLICY IF EXISTS "profiles_update_director" ON profiles;
CREATE POLICY "profiles_update_director" ON profiles FOR UPDATE
  USING (current_role_name() = 'director' AND center_id = my_center());

-- children
DROP POLICY IF EXISTS "children_select" ON children;
CREATE POLICY "children_select" ON children FOR SELECT USING (
  (current_role_name() = 'director' AND center_id = my_center())
  OR teacher_id = auth.uid()
  OR EXISTS (SELECT 1 FROM children_parents WHERE child_id = children.id AND parent_id = auth.uid())
);
DROP POLICY IF EXISTS "children_insert" ON children;
CREATE POLICY "children_insert" ON children FOR INSERT
  WITH CHECK (current_role_name() = 'director' AND center_id = my_center());
DROP POLICY IF EXISTS "children_update" ON children;
CREATE POLICY "children_update" ON children FOR UPDATE
  USING (current_role_name() = 'director' AND center_id = my_center());

-- children_parents (no center_id of its own -> scope via the child's center).
-- Reads the center through child_center(), a SECURITY DEFINER function, NOT
-- a plain EXISTS on `children` (that ran under children_select's RLS, which
-- itself queries children_parents -> infinite recursion; fixed 2026-08-11,
-- fix folded straight into this file, no separate migration).
CREATE OR REPLACE FUNCTION child_center(p_child_id UUID) RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT center_id FROM public.children WHERE id = p_child_id;
$$;
DROP POLICY IF EXISTS "children_parents_select" ON children_parents;
CREATE POLICY "children_parents_select" ON children_parents FOR SELECT USING (
  parent_id = auth.uid()
  OR (current_role_name() = 'director' AND child_center(child_id) = my_center())
);
DROP POLICY IF EXISTS "children_parents_insert" ON children_parents;
CREATE POLICY "children_parents_insert" ON children_parents FOR INSERT WITH CHECK (
  current_role_name() = 'director' AND child_center(child_id) = my_center()
);
DROP POLICY IF EXISTS "children_parents_delete" ON children_parents;
CREATE POLICY "children_parents_delete" ON children_parents FOR DELETE USING (
  current_role_name() = 'director' AND child_center(child_id) = my_center()
);

-- schedule_entries (has center_id)
DROP POLICY IF EXISTS "schedule_entries_select" ON schedule_entries;
CREATE POLICY "schedule_entries_select" ON schedule_entries FOR SELECT USING (
  (current_role_name() = 'director' AND center_id = my_center())
  OR (type = 'teacher' AND current_role_name() = 'teacher')
  OR (type = 'child' AND EXISTS (
        SELECT 1 FROM children WHERE children.id = schedule_entries.ref_id AND children.teacher_id = auth.uid()))
  OR (type = 'child' AND EXISTS (
        SELECT 1 FROM children_parents WHERE children_parents.child_id = schedule_entries.ref_id AND children_parents.parent_id = auth.uid()))
  OR (type = 'class' AND EXISTS (
        SELECT 1 FROM classes WHERE classes.id = schedule_entries.ref_id AND classes.teacher_uid = auth.uid()))
  OR (type = 'class' AND EXISTS (
        SELECT 1 FROM classes cl JOIN children c ON c.class_id = cl.id JOIN children_parents cp ON cp.child_id = c.id
        WHERE cl.id = schedule_entries.ref_id AND cp.parent_id = auth.uid()))
);
DROP POLICY IF EXISTS "schedule_entries_insert" ON schedule_entries;
CREATE POLICY "schedule_entries_insert" ON schedule_entries FOR INSERT WITH CHECK (
  (current_role_name() = 'director' AND center_id = my_center())
  OR (current_role_name() = 'teacher' AND type = 'teacher' AND ref_id = auth.uid())
  OR (type = 'class' AND EXISTS (
        SELECT 1 FROM classes WHERE classes.id = schedule_entries.ref_id AND classes.teacher_uid = auth.uid()))
);
DROP POLICY IF EXISTS "schedule_entries_update" ON schedule_entries;
CREATE POLICY "schedule_entries_update" ON schedule_entries FOR UPDATE USING (
  (current_role_name() = 'director' AND center_id = my_center()) OR created_by = auth.uid()
);
DROP POLICY IF EXISTS "schedule_entries_delete" ON schedule_entries;
CREATE POLICY "schedule_entries_delete" ON schedule_entries FOR DELETE USING (
  (current_role_name() = 'director' AND center_id = my_center()) OR created_by = auth.uid()
);

-- attendance (insert already M3-scoped; scope the director SELECT by center)
DROP POLICY IF EXISTS "attendance_select" ON attendance;
CREATE POLICY "attendance_select" ON attendance FOR SELECT USING (
  (current_role_name() = 'director' AND center_id = my_center())
  OR created_by = auth.uid()
  OR EXISTS (SELECT 1 FROM children_parents WHERE child_id = attendance.child_id AND parent_id = auth.uid())
);
DROP POLICY IF EXISTS "attendance_insert" ON attendance;
CREATE POLICY "attendance_insert" ON attendance FOR INSERT WITH CHECK (
  current_role_name() = 'teacher'
  AND EXISTS (SELECT 1 FROM children WHERE children.id = attendance.child_id AND children.teacher_id = auth.uid())
);

-- daily_reports
DROP POLICY IF EXISTS "daily_reports_select" ON daily_reports;
CREATE POLICY "daily_reports_select" ON daily_reports FOR SELECT USING (
  teacher_id = auth.uid()
  OR (current_role_name() = 'director' AND center_id = my_center())
  OR EXISTS (SELECT 1 FROM children_parents WHERE child_id = daily_reports.child_id AND parent_id = auth.uid())
);
DROP POLICY IF EXISTS "daily_reports_insert" ON daily_reports;
CREATE POLICY "daily_reports_insert" ON daily_reports FOR INSERT WITH CHECK (
  current_role_name() = 'teacher'
  AND EXISTS (SELECT 1 FROM children WHERE children.id = daily_reports.child_id AND children.teacher_id = auth.uid())
);

-- lesson_plans
DROP POLICY IF EXISTS "lesson_plans_select" ON lesson_plans;
CREATE POLICY "lesson_plans_select" ON lesson_plans FOR SELECT USING (
  teacher_id = auth.uid()
  OR (current_role_name() = 'director' AND center_id = my_center())
  OR (status = 'approved' AND EXISTS (
        SELECT 1 FROM classes c WHERE c.id = lesson_plans.class_id AND c.teacher_uid = auth.uid()))
  OR (status = 'approved' AND EXISTS (
        SELECT 1 FROM children ch JOIN children_parents cp ON cp.child_id = ch.id
        WHERE ch.class_id = lesson_plans.class_id AND cp.parent_id = auth.uid()))
);
DROP POLICY IF EXISTS "lesson_plans_update_director" ON lesson_plans;
CREATE POLICY "lesson_plans_update_director" ON lesson_plans FOR UPDATE
  USING (current_role_name() = 'director' AND center_id = my_center())
  WITH CHECK (current_role_name() = 'director' AND center_id = my_center());
DROP POLICY IF EXISTS "lesson_plans_delete" ON lesson_plans;
CREATE POLICY "lesson_plans_delete" ON lesson_plans FOR DELETE USING (
  (current_role_name() = 'director' AND center_id = my_center()) OR teacher_id = auth.uid()
);

-- subjects (center-defined -> scope reads + writes to the caller's center)
DROP POLICY IF EXISTS "subjects_select" ON subjects;
CREATE POLICY "subjects_select" ON subjects FOR SELECT USING (center_id = my_center());
DROP POLICY IF EXISTS "subjects_insert" ON subjects;
CREATE POLICY "subjects_insert" ON subjects FOR INSERT
  WITH CHECK (current_role_name() = 'director' AND center_id = my_center());
DROP POLICY IF EXISTS "subjects_update" ON subjects;
CREATE POLICY "subjects_update" ON subjects FOR UPDATE
  USING (current_role_name() = 'director' AND center_id = my_center());
DROP POLICY IF EXISTS "subjects_delete" ON subjects;
CREATE POLICY "subjects_delete" ON subjects FOR DELETE
  USING (current_role_name() = 'director' AND center_id = my_center());

-- classes (explicit policies — these were never written into the spec; if you
-- already have differently-named classes policies, drop them first).
ALTER TABLE classes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "classes_select" ON classes;
CREATE POLICY "classes_select" ON classes FOR SELECT USING (
  (current_role_name() = 'director' AND center_id = my_center())
  OR teacher_uid = auth.uid()
  OR EXISTS (SELECT 1 FROM children c JOIN children_parents cp ON cp.child_id = c.id
             WHERE c.class_id = classes.id AND cp.parent_id = auth.uid())
);
DROP POLICY IF EXISTS "classes_insert" ON classes;
CREATE POLICY "classes_insert" ON classes FOR INSERT
  WITH CHECK (current_role_name() = 'director' AND center_id = my_center());
DROP POLICY IF EXISTS "classes_update" ON classes;
CREATE POLICY "classes_update" ON classes FOR UPDATE
  USING (current_role_name() = 'director' AND center_id = my_center());
DROP POLICY IF EXISTS "classes_delete" ON classes;
CREATE POLICY "classes_delete" ON classes FOR DELETE
  USING (current_role_name() = 'director' AND center_id = my_center());

-- ---------------------------------------------------------------------
-- M4 — SECURITY DEFINER functions: search_path pinned + center guards on
-- the cascading deletes (a director can only delete within their center).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION complete_password_setup() RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  UPDATE public.profiles SET must_set_password = false, updated_at = now() WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION set_avatar_path(new_path TEXT) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  UPDATE public.profiles SET avatar_path = new_path, updated_at = now() WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION update_own_profile(
  new_name TEXT, new_phone TEXT, new_address TEXT DEFAULT NULL,
  new_dob DATE DEFAULT NULL, new_emergency_contact_name TEXT DEFAULT NULL,
  new_emergency_contact_phone TEXT DEFAULT NULL)
RETURNS public.profiles
LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  UPDATE public.profiles SET
    name = new_name, phone = new_phone, address = new_address, dob = new_dob,
    emergency_contact_name = new_emergency_contact_name,
    emergency_contact_phone = new_emergency_contact_phone, updated_at = now()
  WHERE id = auth.uid() RETURNING *;
$$;

CREATE OR REPLACE FUNCTION sync_profile_email() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  UPDATE public.profiles SET email = NEW.email, updated_at = now() WHERE id = NEW.id;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION delete_class(p_class_id UUID) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF public.current_role_name() <> 'director' THEN RAISE EXCEPTION 'not authorized'; END IF;
  IF (SELECT center_id FROM public.classes WHERE id = p_class_id) IS DISTINCT FROM public.my_center()
    THEN RAISE EXCEPTION 'class is not in your center'; END IF;
  UPDATE public.children SET class_id = NULL WHERE class_id = p_class_id;
  UPDATE public.lesson_plans SET class_id = NULL WHERE class_id = p_class_id;
  DELETE FROM public.schedule_entries WHERE type = 'class' AND ref_id = p_class_id;
  DELETE FROM public.classes WHERE id = p_class_id;
END;
$$;

CREATE OR REPLACE FUNCTION delete_child(p_child_id UUID) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF public.current_role_name() <> 'director' THEN RAISE EXCEPTION 'not authorized'; END IF;
  IF (SELECT center_id FROM public.children WHERE id = p_child_id) IS DISTINCT FROM public.my_center()
    THEN RAISE EXCEPTION 'child is not in your center'; END IF;
  DELETE FROM public.children_parents WHERE child_id = p_child_id;
  DELETE FROM public.attendance WHERE child_id = p_child_id;
  DELETE FROM public.daily_reports WHERE child_id = p_child_id;
  DELETE FROM public.schedule_entries WHERE type = 'child' AND ref_id = p_child_id;
  DELETE FROM public.children WHERE id = p_child_id;
END;
$$;

CREATE OR REPLACE FUNCTION class_plan_subjects(p_class_id UUID)
RETURNS TABLE (plan_id UUID, title TEXT, subject_name TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT lp.id, lp.title, s.name
  FROM public.lesson_plans lp
  LEFT JOIN public.subjects s ON s.id = lp.subject_id
  WHERE lp.class_id = p_class_id AND lp.status = 'approved'
    AND (
      public.current_role_name() = 'director'
      OR EXISTS (SELECT 1 FROM public.classes c WHERE c.id = p_class_id AND c.teacher_uid = auth.uid())
      OR EXISTS (SELECT 1 FROM public.children ch JOIN public.children_parents cp ON cp.child_id = ch.id
                 WHERE ch.class_id = p_class_id AND cp.parent_id = auth.uid())
    );
$$;

-- ---------------------------------------------------------------------
-- L2 — explicit RLS for the private storage buckets. Directors are scoped to
-- their own center (via the target row's center); owners/teachers/parents as
-- documented. Folder [1] of the object path identifies the owning row.
-- (attendance-photos policies already exist; its director-SELECT is
--  re-created here to add the center scope.)
-- ---------------------------------------------------------------------

-- avatars: <user_id>/avatar.jpg — the user themselves, or a director in the
-- same center as that user.
DROP POLICY IF EXISTS "avatars_insert" ON storage.objects;
CREATE POLICY "avatars_insert" ON storage.objects FOR INSERT WITH CHECK (
  bucket_id = 'avatars' AND (
    (storage.foldername(objects.name))[1] = auth.uid()::text
    OR (current_role_name() = 'director' AND EXISTS (
          SELECT 1 FROM profiles p WHERE p.id::text = (storage.foldername(objects.name))[1] AND p.center_id = my_center()))
  )
);
DROP POLICY IF EXISTS "avatars_update" ON storage.objects;
CREATE POLICY "avatars_update" ON storage.objects FOR UPDATE USING (
  bucket_id = 'avatars' AND (
    (storage.foldername(objects.name))[1] = auth.uid()::text
    OR (current_role_name() = 'director' AND EXISTS (
          SELECT 1 FROM profiles p WHERE p.id::text = (storage.foldername(objects.name))[1] AND p.center_id = my_center()))
  )
);
DROP POLICY IF EXISTS "avatars_select" ON storage.objects;
CREATE POLICY "avatars_select" ON storage.objects FOR SELECT USING (
  bucket_id = 'avatars' AND (
    (storage.foldername(objects.name))[1] = auth.uid()::text
    OR (current_role_name() = 'director' AND EXISTS (
          SELECT 1 FROM profiles p WHERE p.id::text = (storage.foldername(objects.name))[1] AND p.center_id = my_center()))
  )
);

-- child-avatars: <child_id>/avatar.jpg — director (same center) writes;
-- select: director(center) / the child's teacher / a linked parent.
DROP POLICY IF EXISTS "child_avatars_insert" ON storage.objects;
CREATE POLICY "child_avatars_insert" ON storage.objects FOR INSERT WITH CHECK (
  bucket_id = 'child-avatars' AND current_role_name() = 'director'
  AND EXISTS (SELECT 1 FROM children WHERE children.id::text = (storage.foldername(objects.name))[1] AND children.center_id = my_center())
);
DROP POLICY IF EXISTS "child_avatars_update" ON storage.objects;
CREATE POLICY "child_avatars_update" ON storage.objects FOR UPDATE USING (
  bucket_id = 'child-avatars' AND current_role_name() = 'director'
  AND EXISTS (SELECT 1 FROM children WHERE children.id::text = (storage.foldername(objects.name))[1] AND children.center_id = my_center())
);
DROP POLICY IF EXISTS "child_avatars_select" ON storage.objects;
CREATE POLICY "child_avatars_select" ON storage.objects FOR SELECT USING (
  bucket_id = 'child-avatars' AND (
    (current_role_name() = 'director' AND EXISTS (
        SELECT 1 FROM children WHERE children.id::text = (storage.foldername(objects.name))[1] AND children.center_id = my_center()))
    OR EXISTS (SELECT 1 FROM children WHERE children.id::text = (storage.foldername(objects.name))[1] AND children.teacher_id = auth.uid())
    OR EXISTS (SELECT 1 FROM children_parents WHERE children_parents.child_id::text = (storage.foldername(objects.name))[1] AND children_parents.parent_id = auth.uid())
  )
);

-- class-avatars: <class_id>/avatar.jpg — director (same center) manages;
-- select: director(center) / the class teacher / a parent of a child in it.
DROP POLICY IF EXISTS "class_avatars_insert" ON storage.objects;
CREATE POLICY "class_avatars_insert" ON storage.objects FOR INSERT WITH CHECK (
  bucket_id = 'class-avatars' AND current_role_name() = 'director'
  AND EXISTS (SELECT 1 FROM classes WHERE classes.id::text = (storage.foldername(objects.name))[1] AND classes.center_id = my_center())
);
DROP POLICY IF EXISTS "class_avatars_update" ON storage.objects;
CREATE POLICY "class_avatars_update" ON storage.objects FOR UPDATE USING (
  bucket_id = 'class-avatars' AND current_role_name() = 'director'
  AND EXISTS (SELECT 1 FROM classes WHERE classes.id::text = (storage.foldername(objects.name))[1] AND classes.center_id = my_center())
);
DROP POLICY IF EXISTS "class_avatars_select" ON storage.objects;
CREATE POLICY "class_avatars_select" ON storage.objects FOR SELECT USING (
  bucket_id = 'class-avatars' AND (
    (current_role_name() = 'director' AND EXISTS (
        SELECT 1 FROM classes WHERE classes.id::text = (storage.foldername(objects.name))[1] AND classes.center_id = my_center()))
    OR EXISTS (SELECT 1 FROM classes WHERE classes.id::text = (storage.foldername(objects.name))[1] AND classes.teacher_uid = auth.uid())
    OR EXISTS (SELECT 1 FROM classes cl JOIN children c ON c.class_id = cl.id JOIN children_parents cp ON cp.child_id = c.id
               WHERE cl.id::text = (storage.foldername(objects.name))[1] AND cp.parent_id = auth.uid())
  )
);

-- daily-report-images: <child_id>/<date>/<n>.jpg — the child's teacher writes;
-- select: that teacher / director(center) / a linked parent.
DROP POLICY IF EXISTS "daily_report_images_insert" ON storage.objects;
CREATE POLICY "daily_report_images_insert" ON storage.objects FOR INSERT WITH CHECK (
  bucket_id = 'daily-report-images' AND current_role_name() = 'teacher'
  AND EXISTS (SELECT 1 FROM children WHERE children.id::text = (storage.foldername(objects.name))[1] AND children.teacher_id = auth.uid())
);
DROP POLICY IF EXISTS "daily_report_images_select" ON storage.objects;
CREATE POLICY "daily_report_images_select" ON storage.objects FOR SELECT USING (
  bucket_id = 'daily-report-images' AND (
    EXISTS (SELECT 1 FROM children WHERE children.id::text = (storage.foldername(objects.name))[1] AND children.teacher_id = auth.uid())
    OR (current_role_name() = 'director' AND EXISTS (
          SELECT 1 FROM children WHERE children.id::text = (storage.foldername(objects.name))[1] AND children.center_id = my_center()))
    OR EXISTS (SELECT 1 FROM children_parents WHERE children_parents.child_id::text = (storage.foldername(objects.name))[1] AND children_parents.parent_id = auth.uid())
  )
);

-- attendance-photos: re-create the director SELECT clause with center scope
-- (insert/update policies stay teacher-scoped as before).
DROP POLICY IF EXISTS "attendance_photos_select" ON storage.objects;
CREATE POLICY "attendance_photos_select" ON storage.objects FOR SELECT USING (
  bucket_id = 'attendance-photos' AND (
    (current_role_name() = 'director' AND EXISTS (
        SELECT 1 FROM children WHERE children.id::text = (storage.foldername(objects.name))[1] AND children.center_id = my_center()))
    OR EXISTS (SELECT 1 FROM children WHERE children.id::text = (storage.foldername(objects.name))[1] AND children.teacher_id = auth.uid())
    OR EXISTS (SELECT 1 FROM children_parents WHERE children_parents.child_id::text = (storage.foldername(objects.name))[1] AND children_parents.parent_id = auth.uid())
  )
);
