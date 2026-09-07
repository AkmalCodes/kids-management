# Schedule Recurrence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A schedule event can repeat daily (weekdays), weekly (unchanged), monthly, or annually, chosen in the edit-event dialog, with correct leap-year behaviour. Existing events stay weekly with no data migration.

**Architecture:** Two additive columns on `schedule_entries` (`recurrence`, `anchor_date`). One pure function `scheduleEntryOccursOn(entry, date)` holds every rule incl. the leap-year clamps; `ScheduleAgendaView._entriesFor` is the single call site, so the teacher / director / parent views are all covered by that one edit. The dialog gains a "Repeats" dropdown; `DayScheduleScreen` threads the choice + anchor date through to the controller.

**Tech Stack:** PostgreSQL/Supabase (additive columns, no RLS change), Flutter, Riverpod 2.x.

**Spec:** `docs/superpowers/specs/2026-09-07-schedule-recurrence-design.md`

## Global Constraints

- Frequency only — no interval ("every 2 weeks"), no end date, no per-occurrence exceptions. One `schedule_entries` row is the whole series; editing rewrites it.
- Existing rows keep behaving as today: `recurrence` defaults to `'weekly'`, weekly is still driven by the existing `day` (weekday name) column, `anchor_date` stays `NULL` on them.
- Leap-year logic lives **only** in `scheduleEntryOccursOn` / its helpers. `_lastDayOfMonth(y, m) => DateTime(y, m + 1, 0).day` (gives 29 for Feb in a leap year). The single special case: an `annually` entry anchored to **29 February** falls back to **28 February** in a non-leap year. A non-Feb annual anchor and every monthly anchor need no special-case beyond the `_lastDayOfMonth` clamp.
- `daily` means **Mon–Fri only** (`date.weekday >= DateTime.monday && <= DateTime.friday`). Never Sat/Sun.
- The dialog's default selection is **Weekly**, seeded from `existing?.recurrence ?? 'weekly'` — an untouched dialog produces exactly today's behaviour.
- Anchor date for an **edit** is `existing.anchorDate ?? widget.date` (never silently re-anchor a monthly event from its clamped occurrence). For a **create** it is `widget.date`. Always written to the controller, daily/weekly included (informational there).
- No RLS change. `schedule_entries_*` policies untouched. No new controller method, no controller test file (repo convention for Supabase controllers).
- Full Flutter suite stays green; report the real count from `flutter test`.
- No `Co-Authored-By` / `Claude-Session` trailer on commits — bare subject line, matching every commit on this branch.

---

### Task 1: Migration SQL

No automated loop — applied by hand in Supabase, per prior practice.

**Files:**
- Create: `docs/superpowers/specs/2026-09-07-schedule-recurrence.sql`

- [ ] **Step 1: Write it**

```sql
-- Recurring schedule events: an entry can repeat daily / weekly / monthly /
-- annually instead of weekly-only. See
-- docs/superpowers/specs/2026-09-07-schedule-recurrence-design.md.
--
-- Additive. No RLS change. Existing rows become weekly series with no
-- backfill (the DEFAULT covers them; anchor_date stays NULL and weekly is
-- still driven by the existing `day` column).
--
-- Run once, by hand, in the Supabase SQL editor.

ALTER TABLE schedule_entries
  ADD COLUMN recurrence TEXT NOT NULL DEFAULT 'weekly'
    CHECK (recurrence IN ('daily', 'weekly', 'monthly', 'annually')),
  ADD COLUMN anchor_date DATE;
```

- [ ] **Step 2: Hand the user the apply + check**

Tell the user: Supabase dashboard for `rpefksoutqsbreiyppee` → SQL Editor → New query → paste the file → Run. Expect `Success. No rows returned.` Then:

```sql
select column_name, data_type from information_schema.columns
where table_name = 'schedule_entries' and column_name in ('recurrence', 'anchor_date');
-- expect: recurrence / text ; anchor_date / date

select recurrence, count(*) from schedule_entries group by recurrence;
-- expect: every existing row -> 'weekly'
```

- [ ] **Step 3: Confirm with the user before Task 5's screen wiring is exercised end-to-end.** Tasks 2–4 and 6 are pure Dart with no live DB dependency (widget tests mock Supabase), so they need not wait; but do not claim the feature works in the app until the user confirms the columns exist.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-09-07-schedule-recurrence.sql
git commit -m "docs: schedule recurrence migration SQL"
```

---

### Task 2: `scheduleEntryOccursOn` recurrence rule

Pure Dart, directly testable — the leap-year core.

**Files:**
- Create: `lib/shared/util/schedule_recurrence.dart`
- Test: `test/shared/util/schedule_recurrence_test.dart`

**Interfaces:**
- Consumes: `ScheduleEntry` — but only its `recurrence` (String), `day` (String, weekday name), and `anchorDate` (`DateTime?`). Task 3 adds `recurrence` / `anchorDate` to the model; this task can be written against those field names now and will compile once Task 3 lands. **Order:** do Task 3 before Task 2's GREEN step, or stub — simplest is to run Task 3 first. The plan orders 2 before 3 for narrative, but the implementer should do 3 then 2 if compiling in isolation. (Either order is fine; both are committed before Task 4.)
- Produces: `bool scheduleEntryOccursOn(ScheduleEntry e, DateTime date)`.

- [ ] **Step 1: Write the failing test**

Create `test/shared/util/schedule_recurrence_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/core/models/schedule.dart';
import 'package:kids_management/shared/util/schedule_recurrence.dart';

ScheduleEntry _entry({
  required String recurrence,
  String day = 'Monday',
  DateTime? anchorDate,
}) =>
    ScheduleEntry(
      id: 'e1',
      type: 'class',
      refId: 'c1',
      centerId: 'ctr1',
      day: day,
      startTime: '08:00',
      endTime: '09:00',
      label: 'X',
      color: '26A69A',
      recurrence: recurrence,
      anchorDate: anchorDate,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      createdBy: 'u1',
      updatedBy: 'u1',
    );

void main() {
  group('daily', () {
    final e = _entry(recurrence: 'daily');
    test('true Mon–Fri, false Sat/Sun', () {
      // 2026-09-07 is a Monday.
      for (var d = 7; d <= 11; d++) {
        expect(scheduleEntryOccursOn(e, DateTime(2026, 9, d)), isTrue, reason: 'day $d');
      }
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 12)), isFalse); // Sat
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 13)), isFalse); // Sun
    });
  });

  group('weekly', () {
    test('matches only its day-of-week', () {
      final e = _entry(recurrence: 'weekly', day: 'Wednesday');
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 9)), isTrue);  // Wed
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 10)), isFalse); // Thu
    });
  });

  group('monthly', () {
    test('the 15th every month', () {
      final e = _entry(recurrence: 'monthly', anchorDate: DateTime(2026, 1, 15));
      expect(scheduleEntryOccursOn(e, DateTime(2026, 2, 15)), isTrue);
      expect(scheduleEntryOccursOn(e, DateTime(2026, 2, 14)), isFalse);
    });

    test('the 31st clamps to the last day of shorter months', () {
      final e = _entry(recurrence: 'monthly', anchorDate: DateTime(2026, 1, 31));
      expect(scheduleEntryOccursOn(e, DateTime(2026, 1, 31)), isTrue);
      expect(scheduleEntryOccursOn(e, DateTime(2026, 2, 28)), isTrue);  // 2026 common year
      expect(scheduleEntryOccursOn(e, DateTime(2026, 2, 27)), isFalse);
      expect(scheduleEntryOccursOn(e, DateTime(2028, 2, 29)), isTrue);  // 2028 leap
      expect(scheduleEntryOccursOn(e, DateTime(2028, 2, 28)), isFalse);
      expect(scheduleEntryOccursOn(e, DateTime(2026, 4, 30)), isTrue);
      expect(scheduleEntryOccursOn(e, DateTime(2026, 4, 29)), isFalse);
    });

    test('null anchorDate never occurs (defensive)', () {
      final e = _entry(recurrence: 'monthly', anchorDate: null);
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 15)), isFalse);
    });
  });

  group('annually', () {
    test('a normal date, every year', () {
      final e = _entry(recurrence: 'annually', anchorDate: DateTime(2026, 3, 15));
      expect(scheduleEntryOccursOn(e, DateTime(2027, 3, 15)), isTrue);
      expect(scheduleEntryOccursOn(e, DateTime(2027, 3, 14)), isFalse);
      expect(scheduleEntryOccursOn(e, DateTime(2027, 4, 15)), isFalse);
    });

    test('Feb-29 anchor: leap years on the 29th, common years on the 28th', () {
      final e = _entry(recurrence: 'annually', anchorDate: DateTime(2024, 2, 29));
      expect(scheduleEntryOccursOn(e, DateTime(2024, 2, 29)), isTrue);
      expect(scheduleEntryOccursOn(e, DateTime(2025, 2, 28)), isTrue);
      expect(scheduleEntryOccursOn(e, DateTime(2025, 3, 1)), isFalse); // day after the fallback
      expect(scheduleEntryOccursOn(e, DateTime(2026, 2, 28)), isTrue);
      expect(scheduleEntryOccursOn(e, DateTime(2027, 2, 28)), isTrue);
      expect(scheduleEntryOccursOn(e, DateTime(2028, 2, 29)), isTrue);
      expect(scheduleEntryOccursOn(e, DateTime(2028, 2, 28)), isFalse);
    });

    test('null anchorDate never occurs (defensive)', () {
      final e = _entry(recurrence: 'annually', anchorDate: null);
      expect(scheduleEntryOccursOn(e, DateTime(2026, 3, 15)), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run it — fails** (`scheduleEntryOccursOn` undefined; and `ScheduleEntry` has no `recurrence`/`anchorDate` until Task 3 — run Task 3 first if needed).

- [ ] **Step 3: Write the implementation**

Create `lib/shared/util/schedule_recurrence.dart`:

```dart
import '../../core/models/schedule.dart';

const _weekdayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

// The last calendar day of a month: day 0 of the next month. Gives 29 for
// February in a leap year, 28 otherwise -- so this doubles as the leap-year
// test (_lastDayOfMonth(y, 2) == 29).
int _lastDayOfMonth(int year, int month) => DateTime(year, month + 1, 0).day;

// The day-of-month an annual entry lands on in `year`. Normally the anchor's
// own day; the one exception is a 29-February anchor in a non-leap year,
// which falls back to the 28th. (No other date can be missing from a year.)
int _annualDayInYear(DateTime anchor, int year) {
  if (anchor.month == 2 && anchor.day == 29 && _lastDayOfMonth(year, 2) != 29) {
    return 28;
  }
  return anchor.day;
}

// Does this recurring entry have an occurrence on `date`? `date`'s time part
// is ignored. Every recurrence rule -- and all the leap-year handling --
// lives here; ScheduleAgendaView._entriesFor is the only caller.
bool scheduleEntryOccursOn(ScheduleEntry e, DateTime date) {
  switch (e.recurrence) {
    case 'daily':
      return date.weekday >= DateTime.monday && date.weekday <= DateTime.friday;
    case 'weekly':
      return _weekdayNames[date.weekday - 1] == e.day;
    case 'monthly':
      final anchor = e.anchorDate;
      if (anchor == null) return false;
      final target =
          anchor.day < _lastDayOfMonth(date.year, date.month)
              ? anchor.day
              : _lastDayOfMonth(date.year, date.month);
      return date.day == target;
    case 'annually':
      final anchor = e.anchorDate;
      if (anchor == null) return false;
      return date.month == anchor.month &&
          date.day == _annualDayInYear(anchor, date.year);
    default:
      return false;
  }
}
```

- [ ] **Step 4: Run the test — passes** (`flutter test test/shared/util/schedule_recurrence_test.dart`).

- [ ] **Step 5: `flutter analyze`** — clean.

- [ ] **Step 6: Commit**

```bash
git add lib/shared/util/schedule_recurrence.dart test/shared/util/schedule_recurrence_test.dart
git commit -m "feat: scheduleEntryOccursOn recurrence rule with leap-year clamps"
```

---

### Task 3: `ScheduleEntry` model + `ScheduleController` params

**Files:**
- Modify: `lib/core/models/schedule.dart`
- Modify: `lib/core/controllers/schedule_controller.dart`
- Test: `test/core/models/schedule_test.dart` (create if absent; otherwise extend)

**Interfaces:**
- Produces:
  - `ScheduleEntry.recurrence` (`String`, from `json['recurrence'] as String? ?? 'weekly'`), `ScheduleEntry.anchorDate` (`DateTime?`, from `DateTime.tryParse(json['anchor_date'] as String? ?? '')` — or explicit null check). Constructor: `recurrence` required, `anchorDate` optional. `toJson` adds `'recurrence': recurrence` and `'anchor_date': anchorDate?.toIso8601String().split('T').first` (or null).
  - `ScheduleController.createEntry` / `updateEntry` gain `required String recurrence` and `DateTime? anchorDate`, written as `'recurrence': recurrence` and `'anchor_date': anchorDate?.toIso8601String().split('T').first`.

- [ ] **Step 1: Failing model test** — assert `fromJson` reads `recurrence` and `anchor_date` (present, and defaulting when absent/null), and `toJson` round-trips. Run — fails.

- [ ] **Step 2: Edit `schedule.dart`** — add the two fields, the constructor params, the `fromJson` lines, the `toJson` keys. Every existing `ScheduleEntry(...)` construction in the test tree will now need `recurrence: 'weekly'` — grep `ScheduleEntry(` under `test/` and add it (the fixtures in `schedule_agenda_view_test.dart`, `day_schedule_screen_test.dart`, `day_timetable_test.dart`, `schedule_entry_form_dialog_test.dart`, and any others). `anchorDate` is optional so only `recurrence` is strictly required.

- [ ] **Step 3: Edit `schedule_controller.dart`** — add the params + payload keys to `createEntry` and `updateEntry`.

- [ ] **Step 4: `flutter analyze`** — clean (this is the gate that every `ScheduleEntry(...)` and every `createEntry`/`updateEntry` call now compiles). Fix each call site the analyzer flags — the real `DayScheduleScreen` call sites are Task 5; here just make them compile by passing `recurrence: 'weekly', anchorDate: widget.date` as a placeholder if analyze demands it, and note in the report that Task 5 replaces those with the dialog's result. If cleaner, leave `schedule.dart` + `schedule_controller.dart` + tests in this task and let Task 5 own the `DayScheduleScreen` edit entirely — but then this task's `flutter analyze` will fail on the two `DayScheduleScreen` call sites. **Chosen:** this task adds `recurrence: 'weekly', anchorDate: widget.date` to the two `DayScheduleScreen` calls as a compiling placeholder; Task 5 swaps them for `result.recurrence` / `result.anchorDate`.

- [ ] **Step 5: `flutter test`** — full suite green. Report count.

- [ ] **Step 6: Commit**

```bash
git add lib/core/models/schedule.dart lib/core/controllers/schedule_controller.dart lib/features/shared/screens/day_schedule_screen.dart test/
git commit -m "feat: ScheduleEntry.recurrence/anchorDate and controller params"
```

---

### Task 4: "Repeats" dropdown in the event dialog

**Files:**
- Modify: `lib/shared/widgets/schedule_entry_form_dialog.dart`
- Modify: `test/shared/widgets/schedule_entry_form_dialog_test.dart`

**Interfaces:**
- Produces:
  - `showScheduleEntryFormDialog` + `_ScheduleEntryFormDialog` gain `required DateTime anchorDate`.
  - `ScheduleEntrySaved` gains `final String recurrence;` and `final DateTime anchorDate;` (constructor params required).
  - A `DropdownButtonFormField<String>` labelled "Repeats" with items `daily` / `weekly` / `monthly` / `annually` (display-cased "Daily" etc.), state `late String _recurrence` seeded from `widget.existing?.recurrence ?? 'weekly'`.
  - A helper `Text` below it (`Theme.of(context).textTheme.bodySmall`, `onSurfaceVariant`) whose content is `_recurrenceHelp(_recurrence, widget.anchorDate)`:
    - `daily` → `'Repeats every weekday'`
    - `weekly` → `'Repeats every ${_weekdayName(anchorDate)}'`
    - `monthly` → `'Repeats on day ${anchorDate.day} each month (the last day in shorter months)'`
    - `annually` → `anchorDate.month == 2 && anchorDate.day == 29 ? 'Repeats every 29 Feb (28 Feb in non-leap years)' : 'Repeats every ${anchorDate.day} ${_monthName(anchorDate.month)}'`
  - `_save` passes `recurrence: _recurrence, anchorDate: widget.anchorDate` into `ScheduleEntrySaved`.

- [ ] **Step 1: Failing tests** — extend `schedule_entry_form_dialog_test.dart`:
  - opening the dialog (add mode) shows a "Repeats" field defaulting to "Weekly";
  - editing an entry with `recurrence: 'monthly'` seeds the field to "Monthly";
  - selecting "Monthly" and Save returns `ScheduleEntrySaved` with `recurrence == 'monthly'` and `anchorDate ==` the passed date;
  - the helper text changes from the weekly string to the monthly string when the selection changes.
  The existing tests need the new required `anchorDate:` arg added to their `showScheduleEntryFormDialog` calls (pick any fixed date, e.g. `DateTime(2026, 9, 9)`).

- [ ] **Step 2: Run — fails.**

- [ ] **Step 3: Implement** the dropdown + helper + result fields per Interfaces. Place the "Repeats" field just under the time pickers, above the lesson-plan dropdown. `_weekdayName` / `_monthName` can be small local `const` lists mirroring the ones already in `day_schedule_screen.dart`.

- [ ] **Step 4: Run the dialog tests — pass. `flutter analyze` — clean.**

- [ ] **Step 5: Commit**

```bash
git add lib/shared/widgets/schedule_entry_form_dialog.dart test/shared/widgets/schedule_entry_form_dialog_test.dart
git commit -m "feat: Repeats dropdown (daily/weekly/monthly/annually) in the event dialog"
```

---

### Task 5: Wire the choice through `DayScheduleScreen`

**Files:**
- Modify: `lib/features/shared/screens/day_schedule_screen.dart`
- Modify: `test/features/shared/screens/day_schedule_screen_test.dart` (path per the repo — confirm)

**Interfaces:**
- Consumes: the dialog's new `anchorDate` param + `ScheduleEntrySaved.recurrence` / `.anchorDate` (Task 4); the controller's new params (Task 3).

- [ ] **Step 1: Failing test** — in the day-screen test: creating an event with the dialog set to "Monthly" calls `createEntry` with `recurrence: 'monthly'` and `anchorDate:` the screen's `date`; editing a `monthly` entry (with its own `anchorDate` two months before the viewed day) calls `updateEntry` with that **original** `anchorDate`, not the viewed date. Mock the dialog result or drive the real dialog — match how the existing day-screen tests exercise `showScheduleEntryFormDialog`.

- [ ] **Step 2: Run — fails.**

- [ ] **Step 3: Implement:**
  - `_addEntry`: `showScheduleEntryFormDialog(context, initialStartTime: startTime, initialEndTime: endTime, anchorDate: widget.date, lessonPlans: _planOptions)`; then `createEntry(..., recurrence: result.recurrence, anchorDate: result.anchorDate)` (drop the Task-3 placeholder).
  - `_tapEntry`: `showScheduleEntryFormDialog(context, existing: entry, anchorDate: entry.anchorDate ?? widget.date, lessonPlans: _planOptions)`; in the `ScheduleEntrySaved` case add `:final recurrence, :final anchorDate` to the pattern and pass `recurrence: recurrence, anchorDate: anchorDate` to `updateEntry`.

- [ ] **Step 4: Run the day-screen tests — pass. `flutter analyze && flutter test` — clean, all green. Report count.**

- [ ] **Step 5: Commit**

```bash
git add lib/features/shared/screens/day_schedule_screen.dart test/
git commit -m "feat: day schedule screen passes recurrence + anchor date on create/edit"
```

---

### Task 6: `ScheduleAgendaView` uses the recurrence rule

**Files:**
- Modify: `lib/shared/widgets/schedule_agenda_view.dart`
- Modify: `test/shared/widgets/schedule_agenda_view_test.dart`

- [ ] **Step 1: Failing tests** — extend `schedule_agenda_view_test.dart` (it already injects `anchorDate` for date-determinism):
  - a `monthly` entry (anchor day 15) in month view shows on exactly one day row;
  - an `annually` entry, Feb-29 anchor, in month view of a **common** year February shows on the 28th;
  - a `daily` entry in week view shows on all five weekday rows and neither weekend row;
  - a `weekly` entry still shows only on its weekday (regression).

- [ ] **Step 2: Run — the monthly/daily/annually ones fail** (matcher is still `e.day == weekdayName`).

- [ ] **Step 3: Implement** — in `_entriesFor`, replace
  `widget.entries.where((e) => e.day == dayName)` with
  `widget.entries.where((e) => scheduleEntryOccursOn(e, date))`
  (import `../util/schedule_recurrence.dart`; `dayName` is now unused — remove it). Update the file's top comment block ("Entries are a recurring weekly pattern (weekday + time, no calendar date)…") to describe daily/weekly/monthly/annually and the leap-year clamps.

- [ ] **Step 4: Run the agenda-view tests — pass. `flutter analyze && flutter test` — clean, all green. Report count.**

- [ ] **Step 5: Commit**

```bash
git add lib/shared/widgets/schedule_agenda_view.dart test/shared/widgets/schedule_agenda_view_test.dart
git commit -m "feat: schedule agenda view expands daily/monthly/annual recurrence"
```

---

### Task 7: Docs

**Files:**
- Modify: `docs/superpowers/specs/2026-09-07-schedule-recurrence-design.md`
- Modify: `docs/superpowers/specs/2026-07-01-childcare-management-design.md`

- [ ] **Step 1:** Flip the recurrence spec status → `implemented 2026-09-07`.
- [ ] **Step 2:** In the main design spec's schedule sections (§6.2 Schedules and the §6.8 class-owned-schedule note), replace the "recurring **weekly** pattern (day-of-week + time)" wording with: an entry now repeats daily (weekdays), weekly, monthly, or annually — a `recurrence` + optional `anchor_date` on `schedule_entries`; monthly clamps to the last day of shorter months and an annual 29-Feb entry falls back to 28 Feb in non-leap years; the rule is `scheduleEntryOccursOn`. Pointer to `2026-09-07-schedule-recurrence-design.md`.
- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-09-07-schedule-recurrence-design.md docs/superpowers/specs/2026-07-01-childcare-management-design.md
git commit -m "docs: record schedule recurrence as implemented"
```

---

## Done when

- The user has run `2026-09-07-schedule-recurrence.sql` and confirmed the two columns exist and existing rows read back as `recurrence = 'weekly'`.
- The edit-event dialog has a "Repeats" dropdown; picking Monthly/Annually and saving makes the event appear on the right dates (incl. Feb clamps) in all three schedule views.
- An untouched dialog still produces a weekly event; every pre-existing weekly event is unchanged on screen.
- `flutter analyze` clean, full suite green (report the real count).
- No `schedule_entries` RLS change; `day` still drives weekly.
