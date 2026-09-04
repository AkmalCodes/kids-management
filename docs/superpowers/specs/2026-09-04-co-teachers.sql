-- Co-teachers on a class: replace classes.teacher_uid (one teacher) with
-- classes.teacher_uids UUID[] (many). See the design spec at
-- docs/superpowers/specs/2026-09-04-co-teachers-design.md for the full
-- reasoning, including why an array column was chosen over a junction table.
--
-- Run this ONCE, by hand, in the Supabase SQL editor (Project -> SQL Editor),
-- top to bottom. The order matters: the teacher_uid column is dropped only at
-- the very end, after every policy that referenced it has been rewritten.
-- Dropping it earlier makes those policies error and breaks the app.

-- 1. Add the array column. NOT NULL DEFAULT '{}' so it is always a real
--    (possibly empty) array -- callers never branch on null.
ALTER TABLE classes ADD COLUMN teacher_uids UUID[] NOT NULL DEFAULT '{}';

-- 2. Backfill: wrap each existing single teacher in a one-element array.
UPDATE classes SET teacher_uids = ARRAY[teacher_uid] WHERE teacher_uid IS NOT NULL;

-- 3. Helper: does the current user share a class with `target`? SECURITY
--    DEFINER so the classes lookup here is not itself re-filtered by classes
--    RLS. Mirrors the style of my_center() / current_role_name().
CREATE OR REPLACE FUNCTION shares_class_with(target UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.classes c
    WHERE auth.uid() = ANY(c.teacher_uids)
      AND target = ANY(c.teacher_uids)
  );
$$;

-- 4. Trigger: an array has no per-element FK, so deleting a teacher's profile
--    does not clear their id from teacher_uids. Do it here. Harmless if it
--    lingers (matches no auth.uid()), so this is tidiness, not security.
CREATE OR REPLACE FUNCTION remove_teacher_from_classes()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  UPDATE public.classes
     SET teacher_uids = array_remove(teacher_uids, OLD.id)
   WHERE OLD.id = ANY(teacher_uids);
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS profiles_after_delete_clear_class_teacher ON profiles;
CREATE TRIGGER profiles_after_delete_clear_class_teacher
  AFTER DELETE ON profiles
  FOR EACH ROW EXECUTE FUNCTION remove_teacher_from_classes();

-- 5. Rewrite every policy / function / storage policy that tested
--    "classes.teacher_uid = auth.uid()".

-- 5a. classes_select
DROP POLICY IF EXISTS "classes_select" ON classes;
CREATE POLICY "classes_select" ON classes FOR SELECT USING (
  (current_role_name() = 'director' AND center_id = my_center())
  OR auth.uid() = ANY(teacher_uids)
  OR EXISTS (SELECT 1 FROM children c JOIN children_parents cp ON cp.child_id = c.id
             WHERE c.class_id = classes.id AND cp.parent_id = auth.uid())
);

-- 5b. schedule_entries_select (only the type='class' teacher branch changes)
DROP POLICY IF EXISTS "schedule_entries_select" ON schedule_entries;
CREATE POLICY "schedule_entries_select" ON schedule_entries FOR SELECT USING (
  (current_role_name() = 'director' AND center_id = my_center())
  OR (type = 'teacher' AND current_role_name() = 'teacher')
  OR (type = 'child' AND EXISTS (
        SELECT 1 FROM children WHERE children.id = schedule_entries.ref_id AND children.teacher_id = auth.uid()))
  OR (type = 'child' AND EXISTS (
        SELECT 1 FROM children_parents WHERE children_parents.child_id = schedule_entries.ref_id AND children_parents.parent_id = auth.uid()))
  OR (type = 'class' AND EXISTS (
        SELECT 1 FROM classes WHERE classes.id = schedule_entries.ref_id AND auth.uid() = ANY(classes.teacher_uids)))
  OR (type = 'class' AND EXISTS (
        SELECT 1 FROM classes cl JOIN children c ON c.class_id = cl.id JOIN children_parents cp ON cp.child_id = c.id
        WHERE cl.id = schedule_entries.ref_id AND cp.parent_id = auth.uid()))
);

-- 5c. schedule_entries_insert (only the type='class' teacher branch changes)
DROP POLICY IF EXISTS "schedule_entries_insert" ON schedule_entries;
CREATE POLICY "schedule_entries_insert" ON schedule_entries FOR INSERT WITH CHECK (
  (current_role_name() = 'director' AND center_id = my_center())
  OR (current_role_name() = 'teacher' AND type = 'teacher' AND ref_id = auth.uid())
  OR (type = 'class' AND EXISTS (
        SELECT 1 FROM classes WHERE classes.id = schedule_entries.ref_id AND auth.uid() = ANY(classes.teacher_uids)))
);

-- 5d. lesson_plans_select (only the approved-teacher branch changes)
DROP POLICY IF EXISTS "lesson_plans_select" ON lesson_plans;
CREATE POLICY "lesson_plans_select" ON lesson_plans FOR SELECT USING (
  teacher_id = auth.uid()
  OR (current_role_name() = 'director' AND center_id = my_center())
  OR (status = 'approved' AND EXISTS (
        SELECT 1 FROM classes c WHERE c.id = lesson_plans.class_id AND auth.uid() = ANY(c.teacher_uids)))
  OR (status = 'approved' AND EXISTS (
        SELECT 1 FROM children ch JOIN children_parents cp ON cp.child_id = ch.id
        WHERE ch.class_id = lesson_plans.class_id AND cp.parent_id = auth.uid()))
);

-- 5e. class_plan_subjects() SECURITY DEFINER function
CREATE OR REPLACE FUNCTION class_plan_subjects(p_class_id UUID)
RETURNS TABLE (plan_id UUID, title TEXT, subject_name TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT lp.id, lp.title, s.name
  FROM public.lesson_plans lp
  LEFT JOIN public.subjects s ON s.id = lp.subject_id
  WHERE lp.class_id = p_class_id AND lp.status = 'approved'
    AND (
      public.current_role_name() = 'director'
      OR EXISTS (SELECT 1 FROM public.classes c WHERE c.id = p_class_id AND auth.uid() = ANY(c.teacher_uids))
      OR EXISTS (SELECT 1 FROM public.children ch JOIN public.children_parents cp ON cp.child_id = ch.id
                 WHERE ch.class_id = p_class_id AND cp.parent_id = auth.uid())
    );
$$;

-- 5f. class_avatars_select storage policy (only the teacher branch changes)
DROP POLICY IF EXISTS "class_avatars_select" ON storage.objects;
CREATE POLICY "class_avatars_select" ON storage.objects FOR SELECT USING (
  bucket_id = 'class-avatars' AND (
    (current_role_name() = 'director' AND EXISTS (
        SELECT 1 FROM classes WHERE classes.id::text = (storage.foldername(objects.name))[1] AND classes.center_id = my_center()))
    OR EXISTS (SELECT 1 FROM classes WHERE classes.id::text = (storage.foldername(objects.name))[1] AND auth.uid() = ANY(classes.teacher_uids))
    OR EXISTS (SELECT 1 FROM classes cl JOIN children c ON c.class_id = cl.id JOIN children_parents cp ON cp.child_id = c.id
               WHERE cl.id::text = (storage.foldername(objects.name))[1] AND cp.parent_id = auth.uid())
  )
);

-- 5g. profiles_select gains a co-teacher branch
DROP POLICY IF EXISTS "profiles_select" ON profiles;
CREATE POLICY "profiles_select" ON profiles FOR SELECT USING (
  id = auth.uid()
  OR (current_role_name() = 'director' AND center_id = my_center())
  OR shares_class_with(id)
);

-- 6. Finally: drop the old column. Nothing references it any more.
ALTER TABLE classes DROP COLUMN teacher_uid;
