# Grid Tile Name Label Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The attendance grid shows a shortened name label (`First L.`) on a single fixed line, so every avatar renders the same size regardless of name length.

**Architecture:** One new pure helper `shortLabelName` in `lib/shared/util/name_display.dart`, and a two-line change inside `AttendanceGridTile.build` to use it with `maxLines: 1`. Nothing else moves.

**Tech Stack:** Flutter, Riverpod 2.x, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-04-grid-tile-name-label-design.md`

## Global Constraints

- This is piece **A** of three. It does **not** touch the two-grid attendance page (piece C) or any co-teacher model (piece B). Stay inside `AttendanceGridTile` and the new helper file.
- Do not change the grid delegate (`crossAxisCount: 4`, `childAspectRatio: 0.72`), the badge, the photo widget, or the tap/long-press behaviour.
- `MarkAttendanceScreen`'s search still matches on the full `child.name`. Only the displayed label shortens.
- `shortLabelName` rules, exact: after `trim()` and splitting on `RegExp(r'\s+')` with empty segments dropped — 0 parts → `''`; 1 part → `parts.first`; 2+ parts → `'${parts.first} ${parts.last[0].toUpperCase()}.'`. The first word keeps its own casing; only the trailing initial is upper-cased.
- The name slot must stay exactly one line tall even for an empty label — render `' '` (a non-breaking space) when `shortLabelName` returns `''`. No hard-coded pixel height, no manual line-height math.
- The full Flutter suite must stay green. Report the real count from `flutter test` output.
- Do not add a `Co-Authored-By` trailer to commits (repo convention — every prior commit on this branch has none).

---

### Task 1: `shortLabelName` helper

Pure Dart, directly testable — no Flutter widgets, no Supabase.

**Files:**
- Create: `lib/shared/util/name_display.dart`
- Test: `test/shared/util/name_display_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `String shortLabelName(String fullName)` — `"Alice"` → `"Alice"`; `"Ammar Ali"` → `"Ammar A."`; `"Muhammad Aariz Danish bin Abdul Rahman"` → `"Muhammad R."`; `""` / `"   "` → `""`. Task 2 imports this from `package:kids_management/shared/util/name_display.dart`.

- [ ] **Step 1: Write the failing test**

Create `test/shared/util/name_display_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/shared/util/name_display.dart';

void main() {
  group('shortLabelName', () {
    test('single word is returned unchanged', () {
      expect(shortLabelName('Alice'), 'Alice');
    });

    test('two words become first word + last initial', () {
      expect(shortLabelName('Ammar Ali'), 'Ammar A.');
    });

    test('three or more words become first word + last initial', () {
      expect(
        shortLabelName('Muhammad Aariz Danish bin Abdul Rahman'),
        'Muhammad R.',
      );
    });

    test('empty or whitespace-only returns an empty string', () {
      expect(shortLabelName(''), '');
      expect(shortLabelName('   '), '');
    });

    test('leading and internal extra whitespace is ignored', () {
      expect(shortLabelName('  Ammar   Ali  '), 'Ammar A.');
    });

    test('the trailing initial is upper-cased even when the name is lower-case', () {
      expect(shortLabelName('nur aisyah'), 'nur A.');
    });

    test('a single-character last word still yields an initial', () {
      expect(shortLabelName('Ali A'), 'Ali A.');
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/shared/util/name_display_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'kids_management/shared/util/name_display.dart'` (file does not exist yet).

- [ ] **Step 3: Write the implementation**

Create `lib/shared/util/name_display.dart`:

```dart
// Shortens a person's full name to a compact grid label: the first word plus
// the last word's initial, e.g. "Ammar Ali Hassan" -> "Ammar H.". This keeps
// the attendance grid tiles' name slot to a single short line, so a long name
// can't wrap and shrink the avatar above it. Used by AttendanceGridTile (and,
// later, the teacher grid that reuses that tile).
String shortLabelName(String fullName) {
  final parts = fullName
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '';
  if (parts.length == 1) return parts.first;
  return '${parts.first} ${parts.last[0].toUpperCase()}.';
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/shared/util/name_display_test.dart`
Expected: PASS — 7 tests.

- [ ] **Step 5: Run analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/shared/util/name_display.dart test/shared/util/name_display_test.dart
git commit -m "feat: shortLabelName grid label helper"
```

---

### Task 2: `AttendanceGridTile` uses the shortened label on one fixed line

**Files:**
- Modify: `lib/features/teacher/widgets/attendance_grid_tile.dart`
- Test: `test/features/teacher/widgets/attendance_grid_tile_test.dart`
- Modify: `docs/superpowers/specs/2026-07-01-childcare-management-design.md`
- Modify: `docs/superpowers/specs/2026-09-01-teacher-attendance-grid-design.md`

**Interfaces:**
- Consumes: `shortLabelName` from Task 1.
- Produces: no API change — `AttendanceGridTile`'s constructor and callbacks are untouched. Only what it renders under the avatar changes.

- [ ] **Step 1: Add the failing tests**

In `test/features/teacher/widgets/attendance_grid_tile_test.dart`, add these two tests inside `main()`, after the existing `'shows the child name'` test:

```dart
  testWidgets('renders the shortened name label, not the full name',
      (tester) async {
    await _pump(tester, child: _child(name: 'Ammar Ali Hassan'));
    expect(find.text('Ammar H.'), findsOneWidget);
    expect(find.text('Ammar Ali Hassan'), findsNothing);
  });

  testWidgets('avatar is the same size regardless of name length',
      (tester) async {
    // The regression this guards: the name Text used to be maxLines: 2 and
    // sat outside the Expanded, so a name that wrapped stole vertical space
    // and shrank the avatar for that one tile.
    await _pump(tester, child: _child(name: 'Alice'));
    final shortNameAvatar = tester.getSize(find.byType(AspectRatio));

    await _pump(
      tester,
      child: _child(name: 'Muhammad Aariz Danish bin Abdul Rahman'),
    );
    final longNameAvatar = tester.getSize(find.byType(AspectRatio));

    expect(longNameAvatar, shortNameAvatar);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/teacher/widgets/attendance_grid_tile_test.dart`
Expected: FAIL — `renders the shortened name label` fails (`find.text('Ammar H.')` finds nothing; the tile still renders the full name). `avatar is the same size regardless of name length` fails (`longNameAvatar` is shorter than `shortNameAvatar` because the two-line name currently steals height).

- [ ] **Step 3: Make the change**

In `lib/features/teacher/widgets/attendance_grid_tile.dart`:

Add the import alongside the existing imports:

```dart
import '../../../shared/util/name_display.dart';
```

Replace the comment above the `Expanded` (currently: *"Expanded rather than a fixed AspectRatio: the name takes its natural height first and the photo absorbs whatever is left. A fixed square overflowed by ~1px at normal text size, and would have overflowed much harder under accessibility text scaling."*) with:

```dart
          // Expanded rather than a fixed AspectRatio: the name below takes a
          // fixed single line (shortLabelName + maxLines: 1) and the photo
          // absorbs the rest, so every avatar comes out the same size. A
          // fixed square here overflowed by ~1px at normal text size and much
          // harder under accessibility text scaling.
```

Replace the name `Text` block (currently):

```dart
          const SizedBox(height: 6),
          Text(
            child.name,
            // Two lines because real names are long -- one line ellipsized
            // most of them away.
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
```

with:

```dart
          const SizedBox(height: 6),
          Builder(
            builder: (context) {
              final label = shortLabelName(child.name);
              return Text(
                // shortLabelName caps the name at "First L." so it can never
                // wrap. The   fallback keeps the slot one line tall if a
                // name is somehow blank -- an empty Text collapses to zero
                // height, which would make that one tile's avatar bigger.
                label.isEmpty ? ' ' : label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              );
            },
          ),
```

(The `Builder` is only to give `label` a local scope without restructuring `build`; if the surrounding code already computes such locals at the top of `build`, put `final label = shortLabelName(child.name);` there instead and drop the `Builder`.)

- [ ] **Step 4: Run the tile tests to verify they pass**

Run: `flutter test test/features/teacher/widgets/attendance_grid_tile_test.dart`
Expected: PASS — all tests, including the two new ones. The pre-existing `'shows the child name'` (`'Alice'` — one word, label unchanged), both overflow tests, the textScale test, and the `CircleAvatar` test stay green.

- [ ] **Step 5: Run the screen test that renders tiles**

Run: `flutter test test/features/teacher/screens/mark_attendance_screen_test.dart`
Expected: PASS unchanged — its fixtures are `'Alice'` / `'Bob'` (single words, label unchanged) and the search test filters on the full `child.name`. If a `find.text` on a tile label unexpectedly breaks, update only that assertion to the shortened label and note it in the task report.

- [ ] **Step 6: Update the design docs**

In `docs/superpowers/specs/2026-07-01-childcare-management-design.md`: find where the attendance grid tile is described and note that the tile shows a shortened label (`First L.`) rather than the full name, to keep avatars uniform.

In `docs/superpowers/specs/2026-09-01-teacher-attendance-grid-design.md`: add one line recording that the tile's name label was changed to `shortLabelName` (`First L.`) so a long name can't wrap and distort the avatar.

- [ ] **Step 7: Run analyze and the full suite**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: `All tests passed!`. Report the real final count — this plan adds 7 helper tests + 2 tile tests to the current baseline; confirm from actual output, do not assume.

- [ ] **Step 8: Commit**

```bash
git add lib/features/teacher/widgets/attendance_grid_tile.dart test/features/teacher/widgets/attendance_grid_tile_test.dart docs/superpowers/specs/2026-07-01-childcare-management-design.md docs/superpowers/specs/2026-09-01-teacher-attendance-grid-design.md
git commit -m "feat: attendance grid tile shows a shortened one-line name"
```

---

## Done when

- `shortLabelName` returns `First L.` for multi-word names, the word itself for single-word names, and `''` for blank input — with unit tests.
- The attendance grid tile renders that label on one line, and its avatar is the same rendered size for a short name and a very long name (asserted by a test).
- `flutter analyze` is clean and the full suite passes.
- No change to search, the grid delegate, the badge, the photo, or tap/long-press.
