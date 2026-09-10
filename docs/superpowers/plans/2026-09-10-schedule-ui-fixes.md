# Schedule / UI Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** (1) Recurrence options become `once / daily / weekly` — drop `monthly` / `annually`, add `once`. (2) Form dialogs scroll instead of overflowing when the keyboard opens. (3) One shared `AppDropdownField` whose popup menu matches the input field width, used app-wide.

**Architecture:** `scheduleEntryOccursOn` loses two `case`s + two helpers and gains a trivial `once` (Y-M-D == anchor). Three `AlertDialog`s wrap their content `Column` in `SingleChildScrollView`. A new `AppDropdownField<T>` = `FormField<T>` → `InputDecorator` → `LayoutBuilder` → `DropdownButton<T>(menuWidth: <field width>)` replaces every `DropdownButtonFormField`; `teacher_multi_select`'s bare `DropdownButton` gets the same `menuWidth`.

**Tech Stack:** PostgreSQL/Supabase (CHECK-constraint swap, no RLS change), Flutter, Riverpod 2.x.

**Spec:** `docs/superpowers/specs/2026-09-10-schedule-ui-fixes-design.md`

## Global Constraints

- `recurrence` values after this: `once | daily | weekly`. No `monthly` / `annually` anywhere (Dart, SQL CHECK, dialog, tests, docs). User confirmed **no existing `monthly`/`annually` rows** — no data conversion.
- `once` occurs iff `anchorDate != null` and its year+month+day equal `date`'s. `daily` = Mon–Fri. `weekly` = `_weekdayNames[date.weekday-1] == e.day` — both unchanged.
- `ScheduleEntry` model, `ScheduleController.createEntry/updateEntry`, and RLS are **unchanged**. `recurrence` stays a `String` default `'weekly'`; `anchor_date` column unchanged.
- `AppDropdownField` call-site API: `AppDropdownField<T>(value:, items: List<DropdownMenuItem<T>>, onChanged:, decoration:, validator:, borderRadius: 16)`. The fix is `DropdownButton(isExpanded: true, menuWidth: constraints.maxWidth, …)` — `DropdownButton` accepts `menuWidth` (Flutter 3.44), `DropdownButtonFormField` does not.
- The full Flutter suite must stay green; report the real count from `flutter test`.
- No `Co-Authored-By` / `Claude-Session` trailer — bare subject line, matching every commit on this branch.

---

### Task 1: Migration SQL — recurrence CHECK constraint

Applied by hand in Supabase, per prior practice.

**Files:**
- Create: `docs/superpowers/specs/2026-09-10-recurrence-once.sql`

- [ ] **Step 1: Write it**

```sql
-- Recurrence options reduced to once / daily / weekly (monthly + annually
-- removed; a single-occurrence "once" added). See
-- docs/superpowers/specs/2026-09-10-schedule-ui-fixes-design.md.
--
-- No data conversion: confirmed there are no monthly/annually rows.
-- Run once, by hand, in the Supabase SQL editor.

-- 1. Confirm the current constraint's name (it should be
--    'schedule_entries_recurrence_check'):
--    select conname from pg_constraint
--    where conrelid = 'schedule_entries'::regclass and contype = 'c';

ALTER TABLE schedule_entries DROP CONSTRAINT IF EXISTS schedule_entries_recurrence_check;
ALTER TABLE schedule_entries
  ADD CONSTRAINT schedule_entries_recurrence_check
  CHECK (recurrence IN ('once', 'daily', 'weekly'));
```

- [ ] **Step 2: Hand the user the apply + check**

> Supabase dashboard `rpefksoutqsbreiyppee` → SQL Editor → New query. First run the `select conname …` (commented at the top) — confirm the constraint is named `schedule_entries_recurrence_check`; if it's something else, substitute that name into the two `ALTER` lines. Then run the two `ALTER TABLE` statements. Expect `Success. No rows returned.`
>
> Verify: `select recurrence, count(*) from schedule_entries group by recurrence;` — every row is `weekly` (or `daily` if you saved any). No `monthly` / `annually`.

- [ ] **Step 3: Confirm with the user before the feature is claimed working end-to-end.** Tasks 2–8 are pure Dart (tests mock Supabase) and need not wait.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-09-10-recurrence-once.sql
git commit -m "docs: recurrence CHECK constraint -> once/daily/weekly"
```

---

### Task 2: `scheduleEntryOccursOn` — once/daily/weekly

**Files:**
- Modify: `lib/shared/util/schedule_recurrence.dart`
- Modify: `test/shared/util/schedule_recurrence_test.dart`

- [ ] **Step 1: Rewrite the test file**

Replace `test/shared/util/schedule_recurrence_test.dart` with (keep the `_entry` helper from the current file — it already has `recurrence` / `anchorDate` params):

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
      id: 'e1', type: 'class', refId: 'c1', centerId: 'ctr1',
      day: day, startTime: '08:00', endTime: '09:00', label: 'X', color: '26A69A',
      recurrence: recurrence, anchorDate: anchorDate,
      createdAt: DateTime(2026), updatedAt: DateTime(2026),
      createdBy: 'u1', updatedBy: 'u1',
    );

void main() {
  group('once', () {
    test('occurs only on its anchor date (same Y-M-D)', () {
      final e = _entry(recurrence: 'once', anchorDate: DateTime(2026, 9, 15));
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 15)), isTrue);
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 15, 23, 59)), isTrue); // time ignored
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 14)), isFalse);
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 16)), isFalse);
      expect(scheduleEntryOccursOn(e, DateTime(2027, 9, 15)), isFalse); // a year later
    });

    test('null anchorDate never occurs', () {
      expect(scheduleEntryOccursOn(_entry(recurrence: 'once'), DateTime(2026, 9, 15)), isFalse);
    });
  });

  group('daily', () {
    final e = _entry(recurrence: 'daily');
    test('true Mon-Fri, false Sat/Sun, across a month boundary', () {
      for (var d = 7; d <= 11; d++) {
        expect(scheduleEntryOccursOn(e, DateTime(2026, 9, d)), isTrue, reason: 'day $d');
      }
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 12)), isFalse); // Sat
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 13)), isFalse); // Sun
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 30)), isTrue);  // Wed
      expect(scheduleEntryOccursOn(e, DateTime(2026, 10, 1)), isTrue);  // Thu
    });
  });

  group('weekly', () {
    test('matches only its day-of-week', () {
      final e = _entry(recurrence: 'weekly', day: 'Wednesday');
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 9)), isTrue);   // Wed
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 10)), isFalse); // Thu
    });
  });

  test('an unknown recurrence never occurs', () {
    expect(scheduleEntryOccursOn(_entry(recurrence: 'monthly', anchorDate: DateTime(2026, 1, 1)),
        DateTime(2026, 2, 1)), isFalse);
  });
}
```

- [ ] **Step 2: Run — fails** (`once` returns false / not handled; the `monthly` case still exists so the last test may pass by luck — the point is the new `once` group fails).

- [ ] **Step 3: Rewrite the implementation**

`lib/shared/util/schedule_recurrence.dart` — delete `_lastDayOfMonth`, `_annualDayInYear`, and the `monthly` / `annually` `case`s. Update the header comment (drop "leap-year handling", list the three cases). Final file:

```dart
import '../../core/models/schedule.dart';

const _weekdayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

// Does this entry have an occurrence on `date`? Time part of `date` is
// ignored. Three recurrences: 'once' (only on anchorDate), 'daily' (Mon-Fri),
// 'weekly' (the entry's `day`). ScheduleAgendaView._entriesFor is the only
// caller.
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

- [ ] **Step 4: Run — passes.** `flutter analyze` — clean.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/util/schedule_recurrence.dart test/shared/util/schedule_recurrence_test.dart
git commit -m "feat: recurrence rule -> once/daily/weekly (drop monthly/annually)"
```

---

### Task 3: Dialog "Repeats" -> Once / Daily / Weekly

**Files:**
- Modify: `lib/shared/widgets/schedule_entry_form_dialog.dart`
- Modify: `test/shared/widgets/schedule_entry_form_dialog_test.dart`

- [ ] **Step 1: Update the failing tests**

In `schedule_entry_form_dialog_test.dart`: change every assertion mentioning `Monthly` / `Weekly`-default that expected 4 options; the dropdown items are now `Once` / `Daily` / `Weekly`. Adjust the recurrence tests:
- add mode shows "Repeats" defaulting to **Weekly**;
- editing an entry with `recurrence: 'once'` seeds the field to "Once";
- selecting **Once** and Save returns `ScheduleEntrySaved(recurrence: 'once', anchorDate: <the passed date>)`;
- the Once helper text reads `'Occurs once on 9 Sep 2026'` for the fixed `_anchor = DateTime(2026, 9, 9)`.
Remove the monthly-specific helper-text test; keep the "editing weekly entry shows its own day in helper text" test.

- [ ] **Step 2: Run — fails.**

- [ ] **Step 3: Implement**

In `schedule_entry_form_dialog.dart`:
- The `DropdownButtonFormField<String>` "Repeats" items become:

```dart
              items: const [
                DropdownMenuItem(value: 'once', child: Text('Once')),
                DropdownMenuItem(value: 'daily', child: Text('Daily')),
                DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
              ],
```

  (Leave `isExpanded: true` / `borderRadius:` / `initialValue: _recurrence` as-is here — Task 7 swaps this whole widget for `AppDropdownField`.)
- `_recurrenceHelp(String recurrence, DateTime anchor, {String? day})` — replace the `monthly` / `annually` branches with a `once` branch, keep `daily` / `weekly`:

```dart
String _recurrenceHelp(String recurrence, DateTime anchor, {String? day}) {
  switch (recurrence) {
    case 'once':
      return 'Occurs once on ${anchor.day} ${_monthName(anchor.month)} ${anchor.year}';
    case 'daily':
      return 'Repeats every weekday';
    case 'weekly':
    default:
      return 'Repeats every ${day ?? _weekdayName(anchor.weekday)}';
  }
}
```

  `_monthName` / `_weekdayName` / the name-list `const`s stay.

- [ ] **Step 4: Run the dialog tests — pass. `flutter analyze && flutter test` — clean, all green.** Report count.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/widgets/schedule_entry_form_dialog.dart test/shared/widgets/schedule_entry_form_dialog_test.dart
git commit -m "feat: Repeats dropdown -> Once/Daily/Weekly"
```

---

### Task 4: Agenda-view tests + comment

**Files:**
- Modify: `lib/shared/widgets/schedule_agenda_view.dart` (comment only)
- Modify: `test/shared/widgets/schedule_agenda_view_test.dart`

- [ ] **Step 1: Update the tests**

In `schedule_agenda_view_test.dart`: delete the `monthly entry shows on exactly one day row…` and `annually entry on Feb 29…` tests. Add:

```dart
  testWidgets('a once entry shows only on its anchor date', (tester) async {
    // _anchor is a fixed injected "today"; put the once entry on a visible day.
    final onceEntry = _entry('once-1', 'Monday', '10:00', '11:00', 'One-off',
        recurrence: 'once', anchorDate: _anchor);
    await tester.pumpWidget(
      _wrap(ScheduleAgendaView(entries: [onceEntry], anchorDate: _anchor)),
    );
    // Week view (default): shows exactly once, on the _anchor day.
    expect(find.text('One-off'), findsOneWidget);
  });
```

Keep the daily (`findsNWidgets(5)` + 2 "No events") and weekly-regression tests.

- [ ] **Step 2: Run — the deleted tests are gone; the new one may pass already (the matcher handles `once` after Task 2). Confirm green.**

- [ ] **Step 3: Update the comment**

`schedule_agenda_view.dart` header block: the recurrence description now reads once / daily (weekdays) / weekly; drop the monthly/annually + leap-year lines.

- [ ] **Step 4: `flutter analyze && flutter test` — clean, all green.** Report count.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/widgets/schedule_agenda_view.dart test/shared/widgets/schedule_agenda_view_test.dart
git commit -m "feat: agenda view recurrence set is once/daily/weekly"
```

---

### Task 5: Form dialogs scroll instead of overflowing

**Files:**
- Modify: `lib/shared/widgets/schedule_entry_form_dialog.dart`
- Modify: `lib/shared/widgets/class_form_dialog.dart`
- Modify: `lib/shared/widgets/person_invite_dialog.dart`
- Test: `test/shared/widgets/schedule_entry_form_dialog_test.dart` (add one)

- [ ] **Step 1: Wrap the content**

In each of the three files, the `AlertDialog(content: Form(key: …, child: Column(mainAxisSize: MainAxisSize.min, …)))` becomes:

```dart
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [ /* unchanged */ ],
          ),
        ),
      ),
```

Nothing else changes.

- [ ] **Step 2: Add a regression test** (in the schedule dialog's test file):

```dart
  testWidgets('does not overflow when the viewport is short (keyboard up)',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 900); // short: ~keyboard open
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(MaterialApp(home: _Harness()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The color swatches (last content row) are still reachable via scroll.
    await tester.scrollUntilVisible(find.byType(_ColorSwatch).first, 100,
        scrollable: find.byType(Scrollable).first);
  });
```

(If `_ColorSwatch` isn't importable, assert `find.byType(SingleChildScrollView)` is present inside the dialog and `takeException()` is null — the core assertion is no overflow.)

- [ ] **Step 3: Run the dialog tests — pass. `flutter analyze && flutter test` — clean, all green.** Report count.

- [ ] **Step 4: Commit**

```bash
git add lib/shared/widgets/schedule_entry_form_dialog.dart lib/shared/widgets/class_form_dialog.dart lib/shared/widgets/person_invite_dialog.dart test/shared/widgets/schedule_entry_form_dialog_test.dart
git commit -m "fix: form dialogs scroll their content instead of overflowing under the keyboard"
```

---

### Task 6: `AppDropdownField<T>`

**Files:**
- Create: `lib/shared/widgets/app_dropdown_field.dart`
- Test: `test/shared/widgets/app_dropdown_field_test.dart`

**Interfaces:**
- Produces: `AppDropdownField<T>({Key? key, required T? value, required List<DropdownMenuItem<T>> items, required ValueChanged<T?> onChanged, InputDecoration? decoration, String? Function(T?)? validator, double borderRadius = 16})` — a `StatelessWidget` wrapping `FormField<T>`.

- [ ] **Step 1: Write the failing test**

`test/shared/widgets/app_dropdown_field_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/shared/widgets/app_dropdown_field.dart';

Future<void> _pump(
  WidgetTester tester, {
  String? value,
  ValueChanged<String?>? onChanged,
  String? Function(String?)? validator,
  double width = 300,
}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: AppDropdownField<String>(
              value: value,
              onChanged: onChanged ?? (_) {},
              validator: validator,
              decoration: const InputDecoration(labelText: 'Pick'),
              items: const [
                DropdownMenuItem(value: 'a', child: Text('Apple')),
                DropdownMenuItem(value: 'b', child: Text('Banana')),
              ],
            ),
          ),
        ),
      ),
    ));

void main() {
  testWidgets('renders the selected item and the label', (tester) async {
    await _pump(tester, value: 'a');
    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('Pick'), findsOneWidget);
  });

  testWidgets('opening and picking fires onChanged and updates the shown value',
      (tester) async {
    String? picked;
    await _pump(tester, value: 'a', onChanged: (v) => picked = v);
    await tester.tap(find.text('Apple'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Banana').last);
    await tester.pumpAndSettle();
    expect(picked, 'b');
    expect(find.text('Banana'), findsOneWidget);
  });

  testWidgets('the built DropdownButton menuWidth equals the field width',
      (tester) async {
    await _pump(tester, value: 'a', width: 280);
    final btn = tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>));
    // The field is 280 wide minus the InputDecorator content padding; assert
    // the menu tracks the LayoutBuilder width, i.e. it is set and < 280.
    expect(btn.menuWidth, isNotNull);
    expect(btn.menuWidth! <= 280 && btn.menuWidth! > 0, isTrue);
  });

  testWidgets('validator error surfaces through the field', (tester) async {
    final formKey = GlobalKey<FormState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Form(
          key: formKey,
          child: AppDropdownField<String>(
            value: null,
            onChanged: (_) {},
            validator: (v) => v == null ? 'Required' : null,
            items: const [DropdownMenuItem(value: 'a', child: Text('Apple'))],
          ),
        ),
      ),
    ));
    formKey.currentState!.validate();
    await tester.pump();
    expect(find.text('Required'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run — fails** (unresolved import).

- [ ] **Step 3: Write the widget**

`lib/shared/widgets/app_dropdown_field.dart`:

```dart
import 'package:flutter/material.dart';

// A DropdownButtonFormField replacement whose popup menu is exactly the
// width of the input field. DropdownButtonFormField gives its menu no
// explicit width, so Flutter sizes it to the button box and it overhangs
// the field. A plain DropdownButton accepts `menuWidth`; we feed it the
// field's own width from a LayoutBuilder.
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

  @override
  Widget build(BuildContext context) {
    return FormField<T>(
      initialValue: value,
      validator: validator,
      builder: (field) {
        final effective = (decoration ?? const InputDecoration())
            .applyDefaults(Theme.of(context).inputDecorationTheme)
            .copyWith(errorText: field.errorText);
        return InputDecorator(
          decoration: effective,
          isEmpty: field.value == null,
          child: LayoutBuilder(
            builder: (context, constraints) => DropdownButton<T>(
              isExpanded: true,
              menuWidth: constraints.maxWidth,
              borderRadius: BorderRadius.circular(borderRadius),
              value: field.value,
              items: items,
              onChanged: (v) {
                field.didChange(v);
                onChanged(v);
              },
              // The InputDecorator draws the box; hide the button's own line.
              underline: const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run the test — passes.** `flutter analyze` — clean. (If the `menuWidth`/`DropdownButton` API differs on the installed Flutter, adjust and note it — `flutter --version` is 3.44, where `DropdownButton.menuWidth` exists.)

- [ ] **Step 5: Commit**

```bash
git add lib/shared/widgets/app_dropdown_field.dart test/shared/widgets/app_dropdown_field_test.dart
git commit -m "feat: AppDropdownField with a field-width popup menu"
```

---

### Task 7: Migrate every dropdown to `AppDropdownField`

**Files:**
- Modify: `lib/features/director/screens/child_detail_screen.dart` (2)
- Modify: `lib/features/director/screens/director_attendance_screen.dart` (1)
- Modify: `lib/features/director/screens/director_lessons_screen.dart` (2)
- Modify: `lib/features/director/screens/enroll_child_screen.dart` (1)
- Modify: `lib/features/shared_lessons/lesson_plan_edit_screen.dart` (2)
- Modify: `lib/shared/widgets/schedule_entry_form_dialog.dart` (2)
- Modify: `lib/shared/widgets/teacher_multi_select.dart` (1 — bare `DropdownButton`)
- Modify: `lib/core/theme/app_theme.dart` (delete `dropdownMenuTheme`)
- Modify: touched screens' test files only where a colour/type assertion changes

- [ ] **Step 1: Swap each `DropdownButtonFormField`**

For each site: `DropdownButtonFormField<X>(isExpanded: true, borderRadius: BorderRadius.circular(16), initialValue: V, decoration: D, items: I, onChanged: C)` → `AppDropdownField<X>(value: V, decoration: D, items: I, onChanged: C)`. Drop `isExpanded` / `borderRadius` (defaults in the wrapper). Add `import '../../../shared/widgets/app_dropdown_field.dart';` (adjust depth per file). None of these sites currently pass a `validator` to the dropdown — if one does, thread it.

- [ ] **Step 2: `teacher_multi_select.dart`**

Its `DropdownButton<String>(isExpanded: true, hint: …, value: null, items: …, onChanged: …)` — wrap in `LayoutBuilder` and add `menuWidth: constraints.maxWidth`. Nothing else.

- [ ] **Step 3: Delete dead theme config**

In `lib/core/theme/app_theme.dart`, remove the `dropdownMenuTheme: DropdownMenuThemeData(menuStyle: MenuStyle(shape: …))` entry and its comment. (`DropdownMenuThemeData` themes the M3 `DropdownMenu`, which the app does not use.)

- [ ] **Step 4: Run analyze + full suite**

`flutter analyze` — `No issues found!` (compile errors here mean a missed arg at a call site).
`flutter test` — all green. The migrated screens' tests find dropdowns by label / option text / `tap` — those keep working through the wrapper. Fix any test that asserted `find.byType(DropdownButtonFormField)` → `AppDropdownField` (or `DropdownButton`). Report the count.

- [ ] **Step 5: Commit**

```bash
git add lib/features lib/shared/widgets lib/core/theme/app_theme.dart test/
git commit -m "refactor: all dropdowns use AppDropdownField (field-width popup); drop dead dropdownMenuTheme"
```

---

### Task 8: Docs

**Files:**
- Modify: `docs/superpowers/specs/2026-09-10-schedule-ui-fixes-design.md`
- Modify: `docs/superpowers/specs/2026-09-07-schedule-recurrence-design.md`
- Modify: `docs/superpowers/specs/2026-07-01-childcare-management-design.md`

- [ ] **Step 1:** Flip `2026-09-10-schedule-ui-fixes-design.md` status → `implemented 2026-09-10`.
- [ ] **Step 2:** `2026-09-07-schedule-recurrence-design.md` — add a top note: **Revised 2026-09-10 — `monthly` / `annually` removed, `once` added; the leap-year sections below are retained as history of removed code.**
- [ ] **Step 3:** `2026-07-01-childcare-management-design.md` §6.2 / §6.8 — recurrence wording → "once / daily (weekdays) / weekly"; remove the monthly-clamp / 29-Feb sentence. Note dropdowns now use `AppDropdownField` (field-width popup) in the look-and-feel section if dropdowns are mentioned there.
- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-09-10-schedule-ui-fixes-design.md docs/superpowers/specs/2026-09-07-schedule-recurrence-design.md docs/superpowers/specs/2026-07-01-childcare-management-design.md
git commit -m "docs: record the once/daily/weekly recurrence and AppDropdownField"
```

---

## Done when

- The user has run `2026-09-10-recurrence-once.sql`; `schedule_entries` accepts only `once`/`daily`/`weekly`.
- The event dialog's "Repeats" shows **Once / Daily / Weekly**; a `once` event appears on exactly its date in all schedule views and nowhere else; `daily`/`weekly` behave as before.
- Typing in the event-name field with the keyboard up no longer overflows — the dialog scrolls.
- Every dropdown's popup menu matches the width of its input field.
- `flutter analyze` clean, full suite green (report the real count).
- `ScheduleEntry`, `ScheduleController`, RLS unchanged; no `monthly`/`annually` anywhere.
