# Recurring schedule events — design

**Date:** 2026-09-07
**Status:** implemented 2026-09-07

## Problem

Every `schedule_entries` row is a **weekly** recurring pattern: a weekday name
(`day`) + a start/end time, no calendar date. The agenda/day views render real
dates but match an entry to a date only by `entry.day == weekdayName(date)`, so
"every Tuesday" is the only recurrence a user can express. The edit-event
dialog has no way to change this. We want the four common frequencies —
**daily, weekly, monthly, annually** — chosen per event, with correct
leap-year behaviour.

## Goals

- An event can repeat daily (weekdays), weekly (unchanged), monthly, or
  annually.
- Existing events keep behaving exactly as today (weekly, by `day`), with no
  migration of their data beyond a column default.
- Leap years are handled explicitly: a monthly event on the 29th–31st and an
  annual event on 29 February both still appear every month / every year.
- The recurrence rule is one pure, unit-tested function; every schedule view
  routes through it.

## Non-goals

- Intervals ("every 2 weeks"). Frequency only; interval is always 1.
- An end date or occurrence count. A series runs forever, as weekly does today.
- Per-occurrence exceptions ("skip this one", "move just this Tuesday"). One
  `schedule_entries` row is the whole series; editing it rewrites the series.
- A separate date picker in the dialog. The anchor date is the day the dialog
  was opened from (the day view already knows its own date).
- Any RLS change. The new columns are additive; `schedule_entries_*` policies
  are untouched.

## Schema

```sql
ALTER TABLE schedule_entries
  ADD COLUMN recurrence TEXT NOT NULL DEFAULT 'weekly'
    CHECK (recurrence IN ('daily', 'weekly', 'monthly', 'annually')),
  ADD COLUMN anchor_date DATE;
```

- `recurrence` — the frequency. `NOT NULL DEFAULT 'weekly'` so every existing
  row is a weekly series with no backfill.
- `anchor_date` — the calendar date the monthly/annual rule is measured from
  (its day-of-month for monthly; its month + day for annually). `NULL` for
  daily and weekly, which don't need it, and `NULL` on all pre-existing rows.
  The app writes it whenever it has a date to write (every create/edit goes
  through the day view), and **requires** it before saving a monthly or
  annual event.

Applied by hand in the Supabase SQL editor, same as prior migrations. No
verification walkthrough beyond "the two columns exist and existing rows read
back as `recurrence = 'weekly'`, `anchor_date = NULL`".

## The recurrence rule — `scheduleEntryOccursOn(ScheduleEntry e, DateTime date) → bool`

New pure function in `lib/shared/util/schedule_recurrence.dart`. `date` is a
local calendar date (time component ignored). Rules:

| `e.recurrence` | occurs on `date` when |
|---|---|
| `daily` | `date.weekday` is Mon–Fri (`DateTime.monday..DateTime.friday`). `day` and `anchorDate` are ignored. |
| `weekly` | `weekdayName(date) == e.day` — unchanged from today. `anchorDate` ignored. |
| `monthly` | `e.anchorDate != null` **and** `date.day == min(e.anchorDate!.day, _lastDayOfMonth(date.year, date.month))`. |
| `annually` | `e.anchorDate != null` **and** `date.month == e.anchorDate!.month` **and** `date.day == _annualDayInYear(e.anchorDate!, date.year)`. |

Helpers (same file):

- `int _lastDayOfMonth(int year, int month) => DateTime(year, month + 1, 0).day;`
  — the trick already used by the agenda view's month length. Gives 29 for
  February in a leap year, 28 otherwise, 30/31 elsewhere.
- `int _annualDayInYear(DateTime anchor, int year)` — returns `anchor.day`,
  **except** when `anchor` is 29 February and `year` is not a leap year, in
  which case it returns `28`. (A non-Feb anchor never needs a fallback; every
  month has its 1st–28th every year, and Feb-29 is the only date that can be
  missing.)
- Leap-year test: `_lastDayOfMonth(year, 2) == 29`, i.e. reuse the same
  helper rather than writing a separate `year % 4` check.

Worked examples the tests must pin:

- monthly, `anchorDate` = 2026-01-31 → occurs 31 Jan, 28 Feb 2026, 31 Mar,
  30 Apr, … and 29 Feb 2028.
- monthly, `anchorDate` = 2026-01-15 → the 15th of every month, always.
- annually, `anchorDate` = 2024-02-29 → 29 Feb 2024, **28** Feb 2025, 28 Feb
  2026, 28 Feb 2027, 29 Feb 2028.
- annually, `anchorDate` = 2026-03-15 → 15 Mar every year.
- daily → every Mon–Fri; never Sat/Sun.

## Model + controller

### `ScheduleEntry` (`lib/core/models/schedule.dart`)

- `final String recurrence;` — from `json['recurrence']`, defaulting to
  `'weekly'` when absent (defensive; the column is `NOT NULL`).
- `final DateTime? anchorDate;` — from `json['anchor_date']`
  (`DateTime.tryParse`, null-tolerant).
- Both added to the constructor (`recurrence` required, `anchorDate`
  optional) and to `toJson` (`'recurrence'`, `'anchor_date'` — the latter as
  `anchorDate?.toIso8601String().substring(0, 10)` or null).

### `ScheduleController` (`lib/core/controllers/schedule_controller.dart`)

`createEntry` and `updateEntry` gain `required String recurrence` and
`DateTime? anchorDate`, written to the two new columns (anchor as a
`yyyy-MM-dd` string, or null). No new method; no test file (repo convention
for Supabase controllers — proven through the widgets that call it).

## Form dialog

`showScheduleEntryFormDialog` (`lib/shared/widgets/schedule_entry_form_dialog.dart`):

- New param `DateTime anchorDate` — **required**. For a new event this is the
  day the dialog was opened from (`DayScheduleScreen`'s `widget.date`). For an
  edit it is `existing.anchorDate ?? widget.date` — so editing a monthly event
  from its clamped Feb-28 occurrence does **not** silently re-anchor it to the
  28th. The dialog has no UI to change the anchor date; it only echoes it.
- New "Repeats" `DropdownButtonFormField` — `Daily` / `Weekly` / `Monthly` /
  `Annually`, seeded from `existing?.recurrence ?? 'weekly'`. So an untouched
  dialog still produces a weekly event — no behaviour change for anyone who
  ignores it.
- A helper `Text` under the dropdown stating the concrete rule for the
  current selection + `anchorDate`:
  - daily → "Repeats every weekday"
  - weekly → "Repeats every {weekday of anchorDate}"
  - monthly → "Repeats on day {anchorDate.day} each month (the last day in
    shorter months)"
  - annually → "Repeats every {day} {month} (28 Feb in non-leap years)" —
    only mention the Feb-29 clause when `anchorDate` is 29 Feb.
- `ScheduleEntrySaved` gains `final String recurrence;` **and**
  `final DateTime anchorDate;` — the dialog echoes back the anchor it was
  given (unchanged; there is no UI to edit it). The caller writes
  `result.anchorDate` to the controller verbatim.
- `DayScheduleScreen`'s create call passes `anchorDate: widget.date` into the
  dialog; its edit call passes `anchorDate: entry.anchorDate ?? widget.date`.
  Both then pass `recurrence: result.recurrence, anchorDate: result.anchorDate`
  into `createEntry` / `updateEntry`.

  Decision, pinned here so the plan doesn't re-open it: **always write the
  anchor date** (daily/weekly included). It is never read for those
  frequencies, storing it costs nothing, and it avoids a branch-on-frequency
  in the screen. `anchor_date` on a weekly row is informational, not
  load-bearing.

## Views

`ScheduleAgendaView._entriesFor(DateTime date)`
(`lib/shared/widgets/schedule_agenda_view.dart`) changes its filter from
`e.day == _weekdayFull[date.weekday - 1]` to
`scheduleEntryOccursOn(e, date)`. That is the only view change:

- the week rows and month rows both call `_entriesFor`;
- `_openDay` passes `_entriesFor(date)` into `DayScheduleScreen`, so the day
  timetable is correct with no change of its own.

The teacher (`teacher_schedule_screen`), director
(`person_schedule_screen`), and parent (`child_schedule_screen`) views all
render through `ScheduleAgendaView`, so they are all covered by this one edit.

The comment block at the top of `schedule_agenda_view.dart` ("Entries are a
recurring weekly pattern (weekday + time, no calendar date)…") is updated to
describe the four frequencies.

## Testing

- **`scheduleEntryOccursOn`** — a dedicated `schedule_recurrence_test.dart`
  covering every row of the worked-examples list above, plus: weekly still
  matches only its `day`; monthly/annually with `anchorDate == null` never
  occur (defensive — the form prevents saving them, but the function must not
  throw); daily is false on a Saturday and Sunday and true Mon–Fri across a
  month boundary.
- **`ScheduleEntry`** — `fromJson` parses `recurrence` / `anchor_date`
  including null and absent; `toJson` round-trips; default is `'weekly'`.
- **`schedule_entry_form_dialog`** — the "Repeats" dropdown defaults to
  Weekly; changing it to Monthly and saving returns
  `ScheduleEntrySaved(recurrence: 'monthly', …)`; the helper text updates
  with the selection. Extend the existing dialog test file.
- **`ScheduleAgendaView`** — with `anchorDate` (injected "today") fixed: a
  `monthly` entry (anchor day 15) shows on exactly one date in the month
  view; an `annually` entry with a Feb-29 anchor shows on 28 Feb in a common
  year in the month view; a `daily` entry shows on all five weekday rows of
  the week view and neither weekend row. Reuse the existing agenda-view test
  harness / fixtures.
- Full Flutter suite stays green; report the real count.

## Open questions

None.
