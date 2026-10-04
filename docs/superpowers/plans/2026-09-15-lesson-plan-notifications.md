# Lesson Plan Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task, one task at a time, stopping after each for the user to test and say go. Do NOT use subagent-driven-development on this plan — the user has standing instructions to work inline (token visibility). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Notify a center's director(s) when a teacher submits a lesson plan, and notify a plan's teacher-author when a director approves or rejects it — in-app, live, via a generic `notifications` table.

**Architecture:** A `SECURITY DEFINER` Postgres trigger on `lesson_plans` (status-change only) inserts rows into a new generic `notifications` table, scoped to the plan's `center_id`. The Flutter side reads it with a Riverpod `StreamProvider` backed by Supabase Realtime (`supabase_flutter`'s `.stream()`), surfaced as a bell icon + badge in both `TeacherShell` and `DirectorShell`, leading to a full-screen list that opens `LessonPlanEditScreen` on tap.

**Tech Stack:** Flutter/Dart, `flutter_riverpod` 2.x, `supabase_flutter` ^2.5.0 (installed: 2.16.0) — `.stream()`/`SupabaseStreamBuilder` for realtime, `mocktail` for widget-level mocking.

## Global Constraints

- Package/import prefix: `package:kids_management/...`.
- Riverpod pattern: a plain `Provider<XController>` per controller (`ref.watch(supabaseClientProvider)` injected), a `StreamProvider`/`FutureProvider` per readable stream/query — see `lib/core/auth/auth_controller.dart` and `lib/core/controllers/schedule_controller.dart`.
- Never `setState(() => _future = _load())` — block body only (`feedback_setstate_no_arrow_future`).
- Model class is `AppNotification`, not `Notification` — collides with Flutter's own `widgets/notifications.dart` class.
- Comment non-obvious code (RLS/trigger reasoning, Riverpod wiring) — this codebase doubles as a learning reference for the user.
- Migration SQL is applied by hand by the user in the Supabase SQL editor (project ref `rpefksoutqsbreiyppee`) — never assume it's already applied; the plan calls out exactly what to run and what to check.
- Full spec: `docs/superpowers/specs/2026-09-15-lesson-plan-notifications-design.md`. Read it once before starting; every task below implements one piece of it.
- Rejection reason needs no new column (asked and settled 2026-10-04): `lesson_plans.review_note` already exists and the director already fills it on reject, so the trigger folds it into the notification `body` via `COALESCE(': ' || NEW.review_note, '')` and `NotificationsScreen` shows it as the row subtitle.

---

## Task 1: Migration — schema, RLS, trigger, realtime publication

**Files:**
- Create: `docs/superpowers/specs/2026-09-15-lesson-plan-notifications.sql`

**Interfaces:**
- Produces: table `notifications(id, user_id, type, status, title, body, entity_id, read_at, created_at, created_by)`; trigger `lesson_plan_status_notify` on `lesson_plans`.

- [x] **Step 1: Write the migration file**

```sql
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
```

- [x] **Step 2: Commit the migration file**

```bash
git add docs/superpowers/specs/2026-09-15-lesson-plan-notifications.sql
git commit -m "docs: lesson plan notifications migration SQL"
```

Landed as `bcc8ce9` (together with this plan file).

- [ ] **Step 3: Hand off to the user to apply and verify** — WAITING ON THE USER as of 2026-10-04

Tell the user: run the whole file in the Supabase dashboard (project `rpefksoutqsbreiyppee`) → **SQL Editor** → **New query** → paste → **Run**. Expect `Success. No rows returned.`

Then verify by hand (this is the only verification for this task — no Dart test covers SQL):
1. As a teacher, submit a plan. Confirm a `SUBMITTED` row appears in `notifications` (Table Editor) for that center's director(s) and **not** for a director in a different center (if one exists to check against).
2. As that director, approve it. Confirm exactly one new `APPROVED` row appears, `user_id` = the plan's `teacher_id`.
3. Reject a different plan with a note. Confirm the `REJECTED` row's `body` contains the note text.

Do not proceed to Task 2 until the user confirms this works.

---

## Task 2: `AppNotification` model

**Files:**
- Create: `lib/core/models/app_notification.dart`
- Test: `test/core/models/app_notification_test.dart`

**Interfaces:**
- Produces: `class AppNotification { id, userId, type, status, title, body, entityId, readAt (DateTime?), createdAt, createdBy (String?) }`, `factory AppNotification.fromJson(Map<String, dynamic>)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/core/models/app_notification.dart';

void main() {
  Map<String, dynamic> baseJson() => {
        'id': 'n-1',
        'user_id': 'director-1',
        'type': 'lesson_plan',
        'status': 'SUBMITTED',
        'title': 'Lesson plan submitted',
        'body': 'Ms. Smith submitted "Colours" for review',
        'entity_id': 'lp-1',
        'created_at': '2026-09-15T09:00:00Z',
      };

  test('fromJson parses required fields with read_at/created_by absent', () {
    final n = AppNotification.fromJson(baseJson());
    expect(n.id, 'n-1');
    expect(n.userId, 'director-1');
    expect(n.type, 'lesson_plan');
    expect(n.status, 'SUBMITTED');
    expect(n.title, 'Lesson plan submitted');
    expect(n.body, 'Ms. Smith submitted "Colours" for review');
    expect(n.entityId, 'lp-1');
    expect(n.readAt, isNull);
    expect(n.createdBy, isNull);
  });

  test('fromJson parses read_at and created_by when present', () {
    final n = AppNotification.fromJson({
      ...baseJson(),
      'read_at': '2026-09-15T10:00:00Z',
      'created_by': 'teacher-1',
    });
    expect(n.readAt, DateTime.parse('2026-09-15T10:00:00Z'));
    expect(n.createdBy, 'teacher-1');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/models/app_notification_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'kids_management'... app_notification.dart` (file doesn't exist yet).

- [ ] **Step 3: Write the model**

```dart
// One row of the generic `notifications` table (see design doc
// 2026-09-15-lesson-plan-notifications-design.md). Named AppNotification,
// not Notification -- Flutter's own framework already defines
// `Notification` (widgets/notifications.dart, used by
// NotificationListener<T extends Notification>); reusing the name would
// collide the moment this file and package:flutter/material.dart are both
// imported unqualified. Same reason AppUser isn't just User.
//
// read-only: the app never writes a full row (only the DB trigger does),
// so there is no toJson -- markRead patches just `read_at` directly.
class AppNotification {
  final String id;
  final String userId;
  final String type;
  final String status;
  final String title;
  final String body;
  final String entityId;
  final DateTime? readAt;
  final DateTime createdAt;
  final String? createdBy;

  const AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.status,
    required this.title,
    required this.body,
    required this.entityId,
    this.readAt,
    required this.createdAt,
    this.createdBy,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        type: json['type'] as String,
        status: json['status'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        entityId: json['entity_id'] as String,
        readAt: json['read_at'] == null
            ? null
            : DateTime.parse(json['read_at'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        createdBy: json['created_by'] as String?,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/models/app_notification_test.dart`
Expected: PASS (2/2).

- [ ] **Step 5: Commit**

```bash
git add lib/core/models/app_notification.dart test/core/models/app_notification_test.dart
git commit -m "feat: AppNotification model"
```

---

## Task 3: `NotificationController` + providers

**Files:**
- Create: `lib/core/controllers/notification_controller.dart`

**Interfaces:**
- Consumes: `AppNotification.fromJson` (Task 2), `supabaseClientProvider` (`lib/core/auth/auth_controller.dart`), `currentUserProvider` (same file).
- Produces: `class NotificationController { Stream<List<AppNotification>> watchNotifications(String userId); Future<void> markRead(String id); }`, `notificationControllerProvider` (`Provider<NotificationController>`), `notificationsProvider` (`StreamProvider<List<AppNotification>>`), `unreadNotificationsCountProvider` (`Provider<int>`).

No dedicated test file for the controller — `LessonPlanController` (closest precedent: same shape, wraps a Supabase table) has none either. The repo's real convention for these thin Supabase CRUD wrappers is "proven through the widgets that call it," and `.stream()`'s return type (`SupabaseStreamBuilder`) isn't practically mockable — `AuthController.userStream`, the only other stream getter in the codebase, isn't unit-tested for the same reason. This task's "test" is `flutter analyze` staying clean; Task 4/5's widget tests exercise it for real via provider overrides.

- [ ] **Step 1: Write the controller + providers**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_controller.dart';
import '../models/app_notification.dart';

// Reads/writes the `notifications` table. RLS: a user sees/updates only
// their own rows. Rows are never inserted by the app -- only by the
// `lesson_plan_status_notify` Postgres trigger (SECURITY DEFINER), so
// there's no createNotification method here. See the design doc.
class NotificationController {
  final SupabaseClient _client;

  NotificationController({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // Live list for one user, newest first. Realtime (`.stream()`) merges an
  // initial fetch with live INSERT/UPDATE/DELETE events -- this is the
  // first use of it in the codebase (see the migration's
  // ALTER PUBLICATION step, required for this to ever emit anything).
  Stream<List<AppNotification>> watchNotifications(String userId) {
    return _client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map(AppNotification.fromJson).toList());
  }

  Future<void> markRead(String id) => _client
      .from('notifications')
      .update({'read_at': DateTime.now().toIso8601String()}).eq('id', id);
}

final notificationControllerProvider = Provider<NotificationController>(
  (ref) => NotificationController(client: ref.watch(supabaseClientProvider)),
);

// Empty stream while signed out/loading -- switches to the real live stream
// the moment currentUserProvider resolves to a user, and back to empty on
// sign-out (ref.watch rebuilds this provider on every AsyncValue change).
final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final user = ref.watch(currentUserProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(notificationControllerProvider).watchNotifications(user.id);
});

// Convenience for the bell badge -- recomputed on every notificationsProvider
// emission either way, so this exists for readability at the call site, not
// as a performance optimization.
final unreadNotificationsCountProvider = Provider<int>((ref) {
  final notifications = ref.watch(notificationsProvider).value ?? const [];
  return notifications.where((n) => n.readAt == null).length;
});
```

- [ ] **Step 2: Verify it compiles clean**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/core/controllers/notification_controller.dart
git commit -m "feat: NotificationController + notificationsProvider (realtime)"
```

---

## Task 4: `NotificationsScreen`

**Files:**
- Create: `lib/shared/screens/notifications_screen.dart`
- Test: `test/shared/screens/notifications_screen_test.dart`

**Interfaces:**
- Consumes: `notificationsProvider` (Task 3), `notificationControllerProvider.markRead` (Task 3), `lessonPlanControllerProvider.getPlan` (`lib/core/controllers/lesson_plan_controller.dart`, exists), `LessonPlanEditScreen(plan:, isDirector:)` (`lib/features/shared_lessons/lesson_plan_edit_screen.dart`, exists).
- Produces: `class NotificationsScreen extends ConsumerWidget { const NotificationsScreen({super.key, required this.isDirector}); final bool isDirector; }`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kids_management/core/models/app_notification.dart';
import 'package:kids_management/core/models/lesson_plan.dart';
import 'package:kids_management/core/controllers/lesson_plan_controller.dart';
import 'package:kids_management/core/controllers/notification_controller.dart';
import 'package:kids_management/features/shared_lessons/lesson_plan_edit_screen.dart';
import 'package:kids_management/shared/screens/notifications_screen.dart';

class MockNotificationController extends Mock implements NotificationController {}

class MockLessonPlanController extends Mock implements LessonPlanController {}

AppNotification _notification({required bool read}) => AppNotification(
      id: 'n-1',
      userId: 'director-1',
      type: 'lesson_plan',
      status: 'SUBMITTED',
      title: 'Lesson plan submitted',
      body: 'Ms. Smith submitted "Colours" for review',
      entityId: 'lp-1',
      readAt: read ? DateTime(2026, 9, 15) : null,
      createdAt: DateTime(2026, 9, 15),
    );

LessonPlan _plan() => LessonPlan(
      id: 'lp-1',
      teacherId: 'teacher-1',
      centerId: 'center-1',
      title: 'Colours',
      content: 'Watercolours',
      status: LessonPlanStatus.submitted,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      createdBy: 'teacher-1',
      updatedBy: 'teacher-1',
    );

void main() {
  late MockNotificationController mockNotifications;
  late MockLessonPlanController mockPlans;

  setUp(() {
    mockNotifications = MockNotificationController();
    mockPlans = MockLessonPlanController();
  });

  Future<void> pumpScreen(WidgetTester tester, List<AppNotification> data) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationsProvider.overrideWith((ref) => Stream.value(data)),
          notificationControllerProvider.overrideWithValue(mockNotifications),
          lessonPlanControllerProvider.overrideWithValue(mockPlans),
        ],
        child: const MaterialApp(home: NotificationsScreen(isDirector: true)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows an empty message when there are no notifications', (tester) async {
    await pumpScreen(tester, []);
    expect(find.text('No notifications yet.'), findsOneWidget);
  });

  testWidgets('lists a notification title and body', (tester) async {
    await pumpScreen(tester, [_notification(read: false)]);
    expect(find.text('Lesson plan submitted'), findsOneWidget);
    expect(find.text('Ms. Smith submitted "Colours" for review'), findsOneWidget);
  });

  testWidgets('tapping a row marks it read and opens the plan editor', (tester) async {
    when(() => mockNotifications.markRead('n-1')).thenAnswer((_) async {});
    when(() => mockPlans.getPlan('lp-1')).thenAnswer((_) async => _plan());

    await pumpScreen(tester, [_notification(read: false)]);
    await tester.tap(find.text('Lesson plan submitted'));
    await tester.pumpAndSettle();

    verify(() => mockNotifications.markRead('n-1')).called(1);
    expect(find.byType(LessonPlanEditScreen), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shared/screens/notifications_screen_test.dart`
Expected: FAIL — `notifications_screen.dart` doesn't exist yet.

- [ ] **Step 3: Write the screen**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/controllers/lesson_plan_controller.dart';
import '../../core/controllers/notification_controller.dart';
import '../../core/models/app_notification.dart';
import '../../features/shared_lessons/lesson_plan_edit_screen.dart';
import '../widgets/app_loader.dart';

// Full-screen notification list, reachable from both TeacherShell and
// DirectorShell (see NotificationBellAction). `isDirector` is passed in
// from the shell -- same pattern LessonPlanEditScreen already uses -- so
// this screen never needs to look up the caller's role itself.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key, required this.isDirector});

  final bool isDirector;

  Future<void> _open(BuildContext context, WidgetRef ref, AppNotification n) async {
    await ref.read(notificationControllerProvider).markRead(n.id);
    // type isn't branched on yet -- only 'lesson_plan' exists -- but this
    // switch is how a second entity type gets added later without a rewrite.
    switch (n.type) {
      case 'lesson_plan':
        final plan = await ref.read(lessonPlanControllerProvider).getPlan(n.entityId);
        if (!context.mounted) return;
        if (plan == null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('That lesson plan no longer exists.')));
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LessonPlanEditScreen(plan: plan, isDirector: isDirector),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: notificationsAsync.when(
        loading: () => const Center(child: AppLoader()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (notifications) {
          if (notifications.isEmpty) {
            return const Center(child: Text('No notifications yet.'));
          }
          return ListView.builder(
            itemCount: notifications.length,
            itemBuilder: (context, i) {
              final n = notifications[i];
              final unread = n.readAt == null;
              return ListTile(
                leading: unread
                    ? Icon(Icons.circle, size: 10, color: Theme.of(context).colorScheme.error)
                    : const SizedBox(width: 10),
                title: Text(
                  n.title,
                  style: TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.normal),
                ),
                subtitle: Text(n.body),
                onTap: () => _open(context, ref, n),
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/shared/screens/notifications_screen_test.dart`
Expected: PASS (3/3).

- [ ] **Step 5: Run the full suite + analyze**

Run: `flutter analyze && flutter test`
Expected: `No issues found!`, all tests pass (report the real count).

- [ ] **Step 6: Commit**

```bash
git add lib/shared/screens/notifications_screen.dart test/shared/screens/notifications_screen_test.dart
git commit -m "feat: NotificationsScreen lists notifications, opens the lesson plan editor on tap"
```

---

## Task 5: Bell icon in both shells

**Files:**
- Create: `lib/shared/widgets/notification_bell_action.dart`
- Test: `test/shared/widgets/notification_bell_action_test.dart`
- Modify: `lib/features/teacher/teacher_shell.dart`
- Modify: `lib/features/director/director_shell.dart`

**Interfaces:**
- Consumes: `unreadNotificationsCountProvider`, `notificationsProvider` (Task 3), `NotificationsScreen` (Task 4).
- Produces: `class NotificationBellAction extends ConsumerWidget { const NotificationBellAction({super.key, required this.isDirector}); final bool isDirector; }`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/core/models/app_notification.dart';
import 'package:kids_management/core/controllers/notification_controller.dart';
import 'package:kids_management/shared/screens/notifications_screen.dart';
import 'package:kids_management/shared/widgets/notification_bell_action.dart';

AppNotification _unread(String id) => AppNotification(
      id: id,
      userId: 'u-1',
      type: 'lesson_plan',
      status: 'SUBMITTED',
      title: 'Lesson plan submitted',
      body: 'body',
      entityId: 'lp-1',
      createdAt: DateTime(2026, 9, 15),
    );

Future<void> _pump(WidgetTester tester, List<AppNotification> data) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [notificationsProvider.overrideWith((ref) => Stream.value(data))],
      child: const MaterialApp(
        home: Scaffold(appBar: AppBar(actions: [NotificationBellAction(isDirector: true)])),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows no badge label when there are no unread notifications', (tester) async {
    await _pump(tester, []);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('shows the unread count on the badge', (tester) async {
    await _pump(tester, [_unread('n-1'), _unread('n-2')]);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('tapping the bell opens NotificationsScreen', (tester) async {
    await _pump(tester, []);
    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationsScreen), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shared/widgets/notification_bell_action_test.dart`
Expected: FAIL — `notification_bell_action.dart` doesn't exist yet.

- [ ] **Step 3: Write the widget**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/controllers/notification_controller.dart';
import '../screens/notifications_screen.dart';

// Bell + unread-count badge, dropped into a shell's AppBar actions.
// `isDirector` is hardcoded by the caller (TeacherShell: false,
// DirectorShell: true) -- same pattern LessonPlanEditScreen's call sites
// already use -- rather than looked up at runtime here.
class NotificationBellAction extends ConsumerWidget {
  const NotificationBellAction({super.key, required this.isDirector});

  final bool isDirector;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadNotificationsCountProvider);
    return IconButton(
      icon: Badge(
        label: Text('$unreadCount'),
        isLabelVisible: unreadCount > 0,
        child: const Icon(Icons.notifications_outlined),
      ),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => NotificationsScreen(isDirector: isDirector)),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/shared/widgets/notification_bell_action_test.dart`
Expected: PASS (3/3).

- [ ] **Step 5: Wire into `TeacherShell`**

Modify `lib/features/teacher/teacher_shell.dart`:

```dart
import 'package:flutter/material.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/notification_bell_action.dart';
import '../profile/profile_screen.dart';
import 'screens/mark_attendance_screen.dart';
import 'screens/teacher_lesson_plans_screen.dart';
import 'screens/teacher_reports_screen.dart';
import 'screens/teacher_schedule_screen.dart';
```

and:

```dart
      appBar: AppBar(
        title: const Text('Childcare Manager'),
        actions: const [NotificationBellAction(isDirector: false)],
      ),
```

- [ ] **Step 6: Wire into `DirectorShell`**

Modify `lib/features/director/director_shell.dart`:

```dart
import 'package:flutter/material.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/notification_bell_action.dart';
import '../profile/profile_screen.dart';
import 'screens/director_attendance_screen.dart';
import 'screens/director_lessons_screen.dart';
import 'screens/director_schedules_screen.dart';
import 'screens/people_screen.dart';
```

and:

```dart
      appBar: AppBar(
        title: const Text('Childcare Manager'),
        actions: const [NotificationBellAction(isDirector: true)],
      ),
```

- [ ] **Step 7: Run the full suite + analyze**

Run: `flutter analyze && flutter test`
Expected: `No issues found!`, all tests pass (report the real count).

- [ ] **Step 8: Commit**

```bash
git add lib/shared/widgets/notification_bell_action.dart test/shared/widgets/notification_bell_action_test.dart lib/features/teacher/teacher_shell.dart lib/features/director/director_shell.dart
git commit -m "feat: notification bell + badge in both shells"
```

---

## Task 6: Docs

**Files:**
- Modify: `docs/superpowers/specs/2026-07-01-childcare-management-design.md`

- [ ] **Step 1: Mark Increment 3 done in §6.5**

Find this line (currently the last bullet of §6.5):

```
- 🔭 **Increment 3 (still to design):** a dashboard + notifications for approval events.
```

Replace with:

```
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
```

- [ ] **Step 2: Update the roadmap table row in §10**

Find:

```
| 7 | Lesson Plans — Increment 1 (subjects + CRUD + approval) + Increment 2 (reusable plans attached to schedule events; subject shown on the event, tap opens the plan) | ✅ Done. Increment 3 (dashboard/notifications) still to design |
```

Replace with:

```
| 7 | Lesson Plans — Increment 1 (subjects + CRUD + approval) + Increment 2 (reusable plans attached to schedule events; subject shown on the event, tap opens the plan) + Increment 3 (notifications for approval events) | ✅ Done. A dashboard view was scoped out of Increment 3 — not yet built |
```

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-07-01-childcare-management-design.md
git commit -m "docs: record lesson plan notifications (Increment 3) as implemented"
```

---

## Done

Report to the user: commits landed, final `flutter analyze`/`flutter test` counts, and the manual verification steps from Task 1 if they haven't run them yet.
