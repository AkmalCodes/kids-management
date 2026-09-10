# Schedule / UI fixes — design

**Date:** 2026-09-10
**Status:** implemented 2026-09-10

## Problem

Three issues surfaced testing the recent schedule-recurrence + theme work:

1. **Recurrence is over-scoped.** `monthly` and `annually` aren't wanted yet;
   what's missing is a **once** option (a single-occurrence event on one
   date).
2. **The event dialog overflows when the keyboard opens.** Typing in the
   "Event name" field raises the keyboard, the dialog shrinks, and its
   content — a bare `Column` with no scroll view — overflows (yellow/black
   stripes). It didn't overflow before the "Repeats" dropdown + helper text
   were added; the extra height is what tips it over now.
3. **Dropdown popup menus don't match their input field's width, app-wide.**
   `DropdownButtonFormField` gives its popup no explicit width, so Flutter
   sizes the menu to the button's render box, which renders **wider** than
   the visible field — the list spans the dialog/screen, not the field it
   belongs to. Every dropdown in the app has this.

## Goals

- `recurrence` values become `once | daily | weekly`. `monthly` / `annually`
  are removed.
- The event dialog (and the other form dialogs with the same shape) scroll
  their content instead of overflowing when the keyboard is up.
- One shared dropdown field widget whose popup menu is exactly the width of
  the input field, used everywhere.

## Non-goals

- Re-adding monthly/annually later is a separate future task; this removes
  them cleanly, it doesn't design their return.
- Migrating to Material 3's `DropdownMenu` widget wholesale. The fix stays
  on `DropdownButton` + `FormField` + `InputDecorator`, just with an
  explicit `menuWidth`.
- Any change to `daily` / `weekly` behaviour, or to `day` still driving
  weekly.
- Restyling the dropdowns beyond the width fix.

## 1. Recurrence: `once / daily / weekly`

### Schema — `docs/superpowers/specs/2026-09-10-recurrence-once.sql`

```sql
ALTER TABLE schedule_entries DROP CONSTRAINT IF EXISTS schedule_entries_recurrence_check;
ALTER TABLE schedule_entries
  ADD CONSTRAINT schedule_entries_recurrence_check
  CHECK (recurrence IN ('once', 'daily', 'weekly'));
```

(The original constraint name is whatever Postgres auto-generated for the
`CHECK (recurrence IN (...))` in `2026-09-07-schedule-recurrence.sql` —
almost certainly `schedule_entries_recurrence_check`. The walkthrough has
the user confirm the real name first with a `\d schedule_entries` /
`information_schema` query, then drop that one.)

No data conversion — the user confirmed no `monthly` / `annually` rows
exist. `anchor_date` stays as-is (`once` uses it; `daily`/`weekly` ignore
it, unchanged from today).

### `scheduleEntryOccursOn` (`lib/shared/util/schedule_recurrence.dart`)

Remove the `monthly` and `annually` `case`s and the `_lastDayOfMonth` /
`_annualDayInYear` helpers (they existed only for those two). The function
becomes:

```dart
bool scheduleEntryOccursOn(ScheduleEntry e, DateTime date) {
  switch (e.recurrence) {
    case 'once':
      final a = e.anchorDate;
      return a != null &&
          a.year == date.year && a.month == date.month && a.day == date.day;
    case 'daily':
      return date.weekday >= DateTime.monday && date.weekday <= DateTime.friday;
    case 'weekly':
      return _weekdayNames[date.weekday - 1] == e.day;
    default:
      return false;
  }
}
```

The header comment loses the "leap-year handling" line and describes the
three cases.

### Dialog (`lib/shared/widgets/schedule_entry_form_dialog.dart`)

- "Repeats" dropdown items → `Once` / `Daily` / `Weekly` (values
  `once` / `daily` / `weekly`), still seeded `existing?.recurrence ?? 'weekly'`.
- `_recurrenceHelp` cases:
  - `once` → `'Occurs once on ${anchor.day} ${_monthName(anchor.month)} ${anchor.year}'`
  - `daily` → `'Repeats every weekday'` (unchanged)
  - `weekly` → `'Repeats every ${day ?? _weekdayName(anchor.weekday)}'` (unchanged)
- Remove the `monthly` / `annually` help branches. `_monthName` stays (now
  used by `once`).

### Model / controller

No change. `recurrence` is still a `String` defaulting to `'weekly'`;
`createEntry` / `updateEntry` still take `recurrence` + `anchorDate`.

### Docs

- `2026-09-07-schedule-recurrence-design.md` — its Status stays `implemented`
  but add a dated **Revised 2026-09-10** note at the top: monthly/annually
  removed, `once` added; the leap-year sections now describe removed code and
  are kept only as history.
- `2026-07-01-childcare-management-design.md` §6.2 / §6.8 — the recurrence
  wording changes from "daily/weekly/monthly/annually" to
  "once / daily (weekdays) / weekly"; drop the leap-year sentence.

## 2. Keyboard overflow — form dialogs

`schedule_entry_form_dialog.dart`, `class_form_dialog.dart`,
`person_invite_dialog.dart` all have `AlertDialog(content: Form(child:
Column(mainAxisSize: MainAxisSize.min, …)))`. Wrap that `Column` in a
`SingleChildScrollView`:

```dart
content: Form(
  key: _formKey,
  child: SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [ … ],
    ),
  ),
),
```

`AlertDialog` already bounds its content's max height; the scroll view lets
the content scroll within that bound instead of overflowing when the
keyboard reduces it. No other change — the field order, validators, and
actions are untouched.

## 3. Dropdown menu width — `AppDropdownField<T>`

### The widget — `lib/shared/widgets/app_dropdown_field.dart`

A drop-in replacement for `DropdownButtonFormField<T>` whose popup menu is
the width of the field.

```dart
class AppDropdownField<T> extends StatelessWidget {
  const AppDropdownField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.decoration,
    this.validator,
    this.borderRadius = 16,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final InputDecoration? decoration;
  final String? Function(T?)? validator;
  final double borderRadius;
  // ...
}
```

Implementation: a `FormField<T>` (`initialValue: value`, `validator:`), whose
builder returns an `InputDecorator` (decoration = the passed one merged with
the app's rounded/filled defaults, plus `errorText` from the field state)
wrapping a `LayoutBuilder` → `DropdownButton<T>`:

```dart
LayoutBuilder(
  builder: (context, constraints) => DropdownButton<T>(
    isExpanded: true,
    menuWidth: constraints.maxWidth,   // <-- the fix
    borderRadius: BorderRadius.circular(borderRadius),
    value: field.value,
    items: items,
    underline: const SizedBox.shrink(),
    onChanged: (v) { field.didChange(v); onChanged(v); },
  ),
)
```

`DropdownButton` (unlike `DropdownButtonFormField`) accepts `menuWidth`;
setting it to the `LayoutBuilder`'s `maxWidth` — the field's own width —
makes the popup exactly match.

### Call sites (migrate all)

`DropdownButtonFormField<…>( isExpanded: true, borderRadius: …, initialValue: X,
decoration: …, items: […], onChanged: … )`  →
`AppDropdownField<…>( value: X, decoration: …, items: […], onChanged: … )`

Eight sites: `child_detail_screen.dart` (×2), `director_attendance_screen.dart`,
`director_lessons_screen.dart` (×2), `enroll_child_screen.dart`,
`lesson_plan_edit_screen.dart` (×2), `schedule_entry_form_dialog.dart` (×2).
Where a site passed `validator:` (child detail / enroll may), thread it
through.

`lib/shared/widgets/teacher_multi_select.dart` uses a bare
`DropdownButton<String>` (not a FormField) — give it
`menuWidth: constraints.maxWidth` via a local `LayoutBuilder`, no wrapper
needed.

### `app_theme.dart`

Delete the `dropdownMenuTheme: DropdownMenuThemeData(...)` block — it only
themes the M3 `DropdownMenu` widget, which the app doesn't use, so it's
dead config. (Leaving it is harmless but it misleads.)

## Testing

- **`scheduleEntryOccursOn`** — rewrite `schedule_recurrence_test.dart`:
  drop every `monthly` / `annually` group; keep `daily` (incl. the
  month-boundary case) and `weekly`; add a `once` group — occurs on exactly
  `anchorDate` (same Y-M-D), not the day before/after, not the same day a
  year later, and `false` when `anchorDate` is null.
- **Dialog** — `schedule_entry_form_dialog_test.dart`: the "Repeats" items
  are Once/Daily/Weekly; default still Weekly; picking Once → `ScheduleEntrySaved(recurrence: 'once')`;
  the help text for Once reads "Occurs once on <date>". Remove any
  monthly/annually assertions.
- **Agenda view** — `schedule_agenda_view_test.dart`: drop the
  monthly/annually tests; add one that a `once` entry shows on its date and
  on no other day in the week/month view. Keep the daily + weekly-regression
  tests.
- **Keyboard overflow** — a widget test per touched dialog that pumps it at
  a short surface height (simulating the keyboard) and asserts
  `tester.takeException()` is null and the fields are still reachable (scroll
  to the last one). At minimum the event dialog.
- **`AppDropdownField`** — widget TDD: renders its items; opening it and
  picking one fires `onChanged` with that value and updates the shown value;
  `validator` surfaces an error via the `InputDecorator`; the `DropdownButton`
  it builds has `menuWidth` equal to the field's width (assert
  `dropdownButton.menuWidth` against the laid-out field width, or assert the
  open menu's width in a golden-free layout check).
- **Migrated screens** — their existing dropdown tests (find by label /
  option text, tap to change) must pass unchanged against `AppDropdownField`.
- Full Flutter suite stays green; report the real count.

## Open questions

None.
