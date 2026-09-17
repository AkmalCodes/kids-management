-- =====================================================================
-- Lesson plan notifications -- run once in the Supabase SQL Editor.
-- See docs/superpowers/specs/2026-09-15-lesson-plan-notifications-design.md
-- =====================================================================

CREATE TABLE notifications (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES profiles(id),   -- recipient
  type        TEXT NOT NULL,                            -- entity kind, e.g. 'lesson_plan'
  status      TEXT NOT NULL,                            -- event, e.g. 'SUBMITTED' | 'APPROVED' | 'REJECTED'
  title       TEXT NOT NULL,
  body        TEXT NOT NULL,
  entity_id   UUID NOT NULL,                            -- lesson_plans.id for this increment
  read_at     TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by  UUID REFERENCES profiles(id)               -- who caused it (submitter / reviewer)
);

CREATE INDEX notifications_user_unread_idx
  ON notifications (user_id, created_at DESC)
  WHERE read_at IS NULL;

-- Own rows only. No INSERT/DELETE policy for regular users at all -- the
-- only writer is the SECURITY DEFINER trigger below, which bypasses RLS.
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY notifications_select ON notifications
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY notifications_update ON notifications
  FOR UPDATE USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Required for the app's realtime stream to receive changes on this table
-- at all -- Supabase does not enable Realtime on a table just because RLS
-- allows reading it.
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;

-- Fires only when lesson_plans.status actually changes (an edit that
-- doesn't touch status, e.g. fixing a typo in draft, inserts nothing).
-- SECURITY DEFINER + pinned search_path so it can read/write profiles and
-- notifications regardless of the caller's own RLS grants -- same pattern
-- as my_center()/current_role_name() (2026-08-07 hardening).
CREATE OR REPLACE FUNCTION notify_lesson_plan_status_change() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  teacher_name TEXT;
BEGIN
  IF NEW.status = 'submitted' THEN
    SELECT name INTO teacher_name FROM public.profiles WHERE id = NEW.teacher_id;

    -- Fan out to every director in the plan's own center. Two separate
    -- casing conventions on purpose: lesson_plans.status is lowercase
    -- (LessonPlanStatus.db), notifications.status is uppercase -- this
    -- trigger is the one place that bridges them.
    INSERT INTO public.notifications (user_id, type, status, title, body, entity_id, created_by)
    SELECT id, 'lesson_plan', 'SUBMITTED',
           'Lesson plan submitted',
           teacher_name || ' submitted "' || NEW.title || '" for review',
           NEW.id, NEW.updated_by
    FROM public.profiles
    WHERE role = 'director' AND center_id = NEW.center_id;

  ELSIF NEW.status IN ('approved', 'rejected') THEN
    -- Always exactly one row: the plan's own author.
    INSERT INTO public.notifications (user_id, type, status, title, body, entity_id, created_by)
    VALUES (
      NEW.teacher_id, 'lesson_plan',
      CASE NEW.status WHEN 'approved' THEN 'APPROVED' ELSE 'REJECTED' END,
      CASE NEW.status WHEN 'approved' THEN 'Lesson plan approved' ELSE 'Lesson plan rejected' END,
      CASE NEW.status
        WHEN 'approved' THEN '"' || NEW.title || '" was approved'
        ELSE '"' || NEW.title || '" was rejected' ||
             COALESCE(': ' || NEW.review_note, '')
      END,
      NEW.id, NEW.reviewed_by
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS lesson_plan_status_notify ON lesson_plans;
CREATE TRIGGER lesson_plan_status_notify
  AFTER UPDATE OF status ON lesson_plans
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION notify_lesson_plan_status_change();
