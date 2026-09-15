# Lesson plan notifications — design

**Date:** 2026-09-15
**Status:** Draft — Pending User Approval

## Problem

Lesson plans (§6.5 of the main design spec) move `draft → submitted →
approved | rejected`. Nobody finds out a transition happened except by
opening the Lessons tab and looking: a teacher submitting a plan doesn't
surface to any director until one happens to browse `DirectorLessonsScreen`,
and a director approving/rejecting doesn't surface to the teacher until they
reopen `TeacherLessonPlansScreen`. This is Increment 3 from the roadmap
(§10): "a dashboard + notifications for approval events."

## Goals

- A director finds out immediately (while the app is open) when a teacher in
  their center submits a plan.
- A teacher finds out immediately when their submitted plan is
  approved/rejected (including the reviewer's note on rejection).
- The underlying table and delivery mechanism are generic enough that a
  second, unrelated notification type (e.g. attendance, daily reports) can
  reuse the same table and UI later with no schema change — only this
  increment's *triggers* are lesson-plan-specific.
- Directors only ever get notified about their own center's activity —
  matches the multi-center RLS scoping already enforced everywhere else
  (`my_center()`, 2026-08-07 hardening).

## Non-goals

- Push notifications (OneSignal). Still Phase 2+ per the original roadmap
  (§2); this increment is in-app only. The table is shaped so a push sender
  can be bolted on later without touching it.
- Email notifications.
- A dashboard/summary screen. The roadmap line bundles "dashboard +
  notifications" but a dashboard is a separate, larger piece of work with its
  own questions (what it shows, for which role) — out of scope here.
- Notifying on `draft` or on an edit that doesn't change `status` (e.g.
  editing a rejected plan back into shape before resubmitting).
- Marking-as-read from anywhere other than opening the notification (no
  "mark all read" bulk action).

## Schema

```sql
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

-- Required for the app's realtime stream (see Model + controller below) to
-- receive changes on this table at all — Supabase does not enable Realtime
-- on a table just because RLS allows reading it. Nothing else in this repo
-- has needed this before now (no prior `.stream()` usage), so it's easy to
-- forget.
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
```

- `type` is the entity kind ("what kind of thing"), `status` is the event
  ("what happened to it") — kept as two separate columns rather than one
  combined string (`'lesson_plan_submitted'`) so a future entity type can
  reuse the same status vocabulary, or vice versa, without string-splitting.
  No `CHECK` constraint on either — a new value is just a new string, no
  migration, matching the "generic table" goal above.
- **Casing is deliberately asymmetric with `lesson_plans.status`**: this
  table's `status` is uppercase (`SUBMITTED`/`APPROVED`/`REJECTED`) while
  `lesson_plans.status` is lowercase (`submitted`/`approved`/`rejected`,
  `LessonPlanStatus.db`). This was a deliberate choice, not an oversight — the
  trigger below is the one place that bridges the two, and it's commented
  there so it isn't mysterious to a future reader.
- `entity_id` has no foreign key to `lesson_plans` (or anything) — it's
  generic across future `type` values, so it can't reference one specific
  table. The app resolves it based on `type`.
- RLS: `notifications_select` and `notifications_update` both
  `USING (user_id = auth.uid())` (own rows only; update is only ever used to
  set `read_at`). **No `INSERT` or `DELETE` policy for regular users at all**
  — the only way a row is created is the trigger below, which runs
  `SECURITY DEFINER` and so bypasses RLS. This avoids ever granting a teacher
  permission to insert a row addressed to a director (or vice versa).

Applied by hand in the Supabase SQL editor, same as prior migrations.

## Trigger

```sql
CREATE OR REPLACE FUNCTION notify_lesson_plan_status_change() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  teacher_name TEXT;
BEGIN
  IF NEW.status = 'submitted' THEN
    SELECT name INTO teacher_name FROM public.profiles WHERE id = NEW.teacher_id;
    INSERT INTO public.notifications (user_id, type, status, title, body, entity_id, created_by)
    SELECT id, 'lesson_plan', 'SUBMITTED',
           'Lesson plan submitted',
           teacher_name || ' submitted "' || NEW.title || '" for review',
           NEW.id, NEW.updated_by
    FROM public.profiles
    WHERE role = 'director' AND center_id = NEW.center_id;

  ELSIF NEW.status IN ('approved', 'rejected') THEN
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

CREATE TRIGGER lesson_plan_status_notify
  AFTER UPDATE OF status ON lesson_plans
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION notify_lesson_plan_status_change();
```

- `WHEN (OLD.status IS DISTINCT FROM NEW.status)` is what keeps a no-op save
  (edit content without changing status) silent — the trigger body never
  even runs.
- `submitted` fans out to every director in `NEW.center_id` (could be zero
  rows if a center somehow has none — not an error, just nothing inserted).
  `approved`/`rejected` always targets exactly one row, the plan's own
  `teacher_id`.
- `SET search_path = ''` + fully-qualified `public.` table names, per the
  M4 hardening pattern already used by `my_center()`/`current_role_name()`.
- Fires regardless of *how* the status changed (app bug, SQL editor, future
  code path) — can't be silently bypassed the way an app-side insert could
  be by a failed/partial client call.

**Your manual verification step** (same shape as every prior migration): run
the `CREATE TABLE`/RLS/trigger SQL in the Supabase SQL editor, then submit a
real plan as a teacher and confirm a `SUBMITTED` row appears for that
center's director(s) but not for a director in a different center; approve
it and confirm exactly one `APPROVED` row appears for the author.

## Model + controller + provider

### `Notification` (`lib/core/models/notification.dart`)

Mirrors the shape of `LessonPlan`: `id`, `userId`, `type`, `status`, `title`,
`body`, `entityId`, `readAt` (nullable), `createdAt`, `createdBy` (nullable).
`fromJson` only — the app never writes a full row, only patches `read_at`.

### `NotificationController` (`lib/core/controllers/notification_controller.dart`)

- `Stream<List<Notification>> watchNotifications()` — Supabase Realtime
  stream on `notifications`, filtered `user_id = auth.uid()`, ordered
  `created_at desc`. Same shape as `currentUserProvider`'s underlying stream.
- `Future<void> markRead(String id)` — `UPDATE ... SET read_at = now()`.

### `notificationsProvider` (`StreamProvider<List<Notification>>`)

Wraps `watchNotifications()`. `unreadNotificationsCountProvider` derives the
badge count (`.where((n) => n.readAt == null).length`) from it. This is a
readability convenience at the call site (the bell icon just wants a number),
not a performance optimization — every emission of the underlying stream
still recomputes it, same as any `Provider` built on a `StreamProvider`.

## UI

- **Bell icon**: `IconButton(icon: Icon(Icons.notifications_outlined))` added
  to `actions:` on the `AppBar` in `TeacherShell` and `DirectorShell` (neither
  has any `actions` today), wrapped in Flutter's built-in Material 3 `Badge`
  (`Badge(label: Text('$count'), isLabelVisible: count > 0, child: ...)`) —
  no hand-rolled positioned dot needed, and no existing count-badge widget in
  the codebase to reuse (the bottom-nav "pip" is a *selection* indicator, a
  different thing).
- **`NotificationsScreen`** (`lib/shared/screens/notifications_screen.dart`,
  reachable from both shells since a teacher and a director both need it):
  full-screen list, newest first, unread rows visually distinct (bold title
  or a leading dot — match whatever the codebase's existing "unread"/"unseen"
  convention is; if there isn't one yet, bold + a colored dot). Tapping a row:
  1. calls `markRead(notification.id)`,
  2. fetches the plan via `LessonPlanController.getPlan(notification.entityId)`
     (already exists) and navigates to **`LessonPlanEditScreen(plan: plan,
     isDirector: <from currentUserProvider's role>)`** — not the read-only
     `LessonPlanViewScreen` (that one has no status chip, no review note, and
     no Approve/Reject controls — it's built for tapping a schedule event,
     not for acting on a notification). `LessonPlanEditScreen` already
     branches on `isDirector` to show Approve/Reject vs edit/resubmit, so a
     director's "submitted" notification and a teacher's "rejected"
     notification both land somewhere they can actually act, with the
     reviewer's note visible. If `getPlan` returns null (plan deleted since
     the notification fired), show a snackbar instead of navigating.

  `type` isn't branched on yet (only `'lesson_plan'` exists), but the
  navigation call is written as a `switch (notification.type)` with one case
  today, so adding a second entity type later is additive, not a rewrite.

## Testing

- `Notification.fromJson` — parses all fields, `read_at` null and non-null.
- `NotificationController` — **no dedicated test file.** `LessonPlanController`
  (the closest precedent — same shape, wraps a Supabase table) has none
  either; the repo's actual convention for these thin Supabase CRUD wrappers
  is "proven through the widgets that call it," not mocked in isolation
  (mocking `.stream()`'s concrete `SupabaseStreamBuilder` return type isn't
  practical anyway — `AuthController.userStream`, the one other stream
  getter in the codebase, isn't unit-tested either, for the same reason).
- `NotificationsScreen` — widget test: renders a list from a fake unread/read
  mix, tapping a row calls `markRead` and navigates to `LessonPlanEditScreen`
  with the right `isDirector`.
- No Dart test for the trigger itself (repo convention: SQL logic is
  verified by the manual walkthrough above, not a Dart test — same as every
  prior migration).
- Full Flutter suite stays green; report the real count.

## Open questions

None.
