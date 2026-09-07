# Theme: Soft Pink on White Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Flip the light theme so pure white is the dominant surface and soft pink (`#FDB0C0`) is an accent — used for the selected nav pill, `FilledButton`s, focus rings + selection controls, and small header/chip tints. The bars carry only a faint pink wash.

**Architecture:** Almost entirely `lib/core/theme/app_theme.dart`: `ColorScheme.fromSeed(...).copyWith(surface: white, primary: seed, onPrimary: dark-rose)`, `scaffoldBackgroundColor: white`, bar backgrounds → a new `barTint` token, nav indicator → `primary`. One hand-rolled widget (`AppBottomNav`) hard-codes scheme colours and is updated to match; two other files that read `colorScheme.primary` are audited; the Piece-C `_SectionDivider` label gets `primary`; a `chipTheme` gives role chips a pink tint.

**Tech Stack:** Flutter (Material 3), Riverpod (unaffected).

**Spec:** `docs/superpowers/specs/2026-09-07-theme-pink-on-white-design.md`

## Global Constraints

- Light theme only. No dark theme. No change to the font (Nunito), corner `radius`, button padding, or any layout.
- One source of truth: `AppTheme`. Tokens: `seed = Color(0xFFFDB0C0)` (rename the existing `seedColor` in place — do not keep both), `onAccent = Color(0xFF5A2A33)`, `barTint = Color(0xFFFFF2F5)`.
- `ColorScheme` = `ColorScheme.fromSeed(seedColor: AppTheme.seed).copyWith(surface: Colors.white, primary: AppTheme.seed, onPrimary: AppTheme.onAccent)`. Everything else derived stays (`surfaceContainerHighest` for input fill, `onSurfaceVariant` for secondary text, `error`, `primaryContainer`, …).
- `scaffoldBackgroundColor: Colors.white` (explicit, even though `surface` now equals it).
- Do NOT touch `lib/core/constants/schedule_colors.dart` (user-chosen event tags) or the attendance status badge green/red/amber (semantic).
- Full Flutter suite stays green; report the real count. Colour assertions in existing tests that break get updated to the new token, not deleted.
- No `Co-Authored-By` / `Claude-Session` trailer — bare subject line.

---

### Task 1: `AppTheme` — white base, pink accent, faint bars

**Files:**
- Modify: `lib/core/theme/app_theme.dart`
- Test: `test/core/theme/app_theme_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `test/core/theme/app_theme_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/core/theme/app_theme.dart';

void main() {
  final t = AppTheme.light;

  test('white is the base surface', () {
    expect(t.scaffoldBackgroundColor, Colors.white);
    expect(t.colorScheme.surface, Colors.white);
  });

  test('soft pink is the primary accent', () {
    expect(t.colorScheme.primary, AppTheme.seed);
    expect(t.colorScheme.onPrimary, AppTheme.onAccent);
  });

  test('the bars carry the faint pink wash, not a filled pink', () {
    expect(t.appBarTheme.backgroundColor, AppTheme.barTint);
    expect(t.navigationBarTheme.backgroundColor, AppTheme.barTint);
  });

  test('the selected nav indicator is the pink accent', () {
    expect(t.navigationBarTheme.indicatorColor, AppTheme.seed);
  });
}
```

- [ ] **Step 2: Run — fails** (`AppTheme.seed` / `onAccent` / `barTint` don't exist; values differ).

- [ ] **Step 3: Edit `app_theme.dart`**

- Replace `static const seedColor = Color(0xFFFDB0C0);` with:

```dart
  static const seed = Color(0xFFFDB0C0);      // soft pink — the accent colour
  static const onAccent = Color(0xFF5A2A33);  // dark rose — text/icons ON soft pink
  static const barTint = Color(0xFFFFF2F5);   // faint wash on the top/bottom bars
```

- In `light`:

```dart
    final colorScheme = ColorScheme.fromSeed(seedColor: seed).copyWith(
      surface: Colors.white,
      primary: seed,
      onPrimary: onAccent,
    );
```

- `scaffoldBackgroundColor: Colors.white,`
- Delete the `final barColor = colorScheme.primaryContainer;` line and its comment; use `barTint` directly.
- `appBarTheme`: `backgroundColor: barTint`, `foregroundColor: colorScheme.onSurface`. Keep everything else (shape, elevation 0, toolbarHeight 48).
- `navigationBarTheme`: `backgroundColor: barTint`, `indicatorColor: seed`. Keep the rest (elevation, height, indicatorShape, labelTextStyle). The `labelTextStyle` colour is currently unset (inherits) — leave it; `_NavItem` in `AppBottomNav` is what actually renders labels.
- `inputDecorationTheme.focusedBorder`: already `BorderSide(color: colorScheme.primary, width: 2)` → now soft pink automatically. No edit.
- Add a `chipTheme`:

```dart
      chipTheme: ChipThemeData(
        backgroundColor: seed.withValues(alpha: 0.15),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
```

- [ ] **Step 4: Run the test — passes. `flutter analyze` — clean.**

- [ ] **Step 5: Full suite** — `flutter test`. Existing tests that assert `primaryContainer` / `onPrimaryContainer` / a pink bar colour will fail; list them and fix each to the new token (`barTint`, `seed`, `onAccent`, `onSurface`) in this task or note them for Task 2/3 if they belong to `AppBottomNav`. Report the count.

- [ ] **Step 6: Commit**

```bash
git add lib/core/theme/app_theme.dart test/core/theme/app_theme_test.dart
git commit -m "feat: white base with soft-pink accents; faint bar wash"
```

---

### Task 2: `AppBottomNav` — pink pill on a faint bar

**Files:**
- Modify: `lib/shared/widgets/app_bottom_nav.dart`
- Modify: `test/shared/widgets/app_bottom_nav_test.dart` (confirm path/name)

- [ ] **Step 1: Failing test** — extend the bottom-nav test: the bar `Material`'s colour is `AppTheme.barTint`; the sliding highlight `DecoratedBox`'s colour is `scheme.primary` (soft pink); a selected item's icon/label colour is `AppTheme.onAccent`. (Match how the existing test reaches those widgets — likely `tester.widget<Material>` / `find.byType(DecoratedBox)`.)

- [ ] **Step 2: Run — fails.**

- [ ] **Step 3: Edit `app_bottom_nav.dart`**

- Import `../../core/theme/app_theme.dart`.
- Bar `Material(color: scheme.primaryContainer)` → `Material(color: AppTheme.barTint)`.
- Sliding highlight `DecoratedBox(decoration: BoxDecoration(color: scheme.surface, …))` → `color: scheme.primary`.
- `_NavItem`'s `fg`: `selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant` → `selected ? AppTheme.onAccent : scheme.onSurfaceVariant`.
- Keep the `boxShadow` (it now does the work of separating the near-white bar from the white body) and everything else.

- [ ] **Step 4: Run the bottom-nav tests — pass. `flutter analyze` — clean.**

- [ ] **Step 5: Commit**

```bash
git add lib/shared/widgets/app_bottom_nav.dart test/shared/widgets/app_bottom_nav_test.dart
git commit -m "feat: bottom nav — pink selection pill on a faint bar"
```

---

### Task 3: Accent audit — section headers + the hard-coded scheme reads

**Files:**
- Modify: `lib/features/teacher/screens/mark_attendance_screen.dart` (the `_SectionDivider` label)
- Review (change only if needed): `lib/features/auth/login_screen.dart`, `lib/features/teacher/widgets/attendance_grid_tile.dart`, `lib/shared/widgets/app_loader.dart`
- Modify tests only where a colour assertion changes.

- [ ] **Step 1:** `_SectionDivider` in `mark_attendance_screen.dart` — its label `style` currently uses `Theme.of(context).colorScheme.onSurfaceVariant`. Change to `colorScheme.primary` so the `——— TEACHERS ———` / `——— CHILDREN ———` headers read as the pink accent the design calls for. If a `mark_attendance_screen_test` asserts the label colour, update it; if it only asserts the text, no test change.

- [ ] **Step 2: Audit — run the app or read each site:**
  - `attendance_grid_tile.dart` `colors.primaryContainer` (photo placeholder bg): `primaryContainer` is **not** overridden by the `copyWith`, so it stays a soft pink tint — fine as a placeholder behind the white grid. **No change** unless it visibly clashes; note the decision in the report.
  - `login_screen.dart:~90` `colorScheme.primary`: now the literal soft pink. If it's an icon/accent, fine. If it's text on white and hard to read, switch that one to `colorScheme.onSurface`. Report which.
  - `app_loader.dart` `colorScheme.primary`: a soft-pink spinner on white — acceptable. **No change.**

- [ ] **Step 3: `flutter analyze && flutter test`** — clean, all green. Report the count.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: pink section headers; accent-colour audit for the new theme"
```

---

### Task 4: Docs

**Files:**
- Modify: `docs/superpowers/specs/2026-09-07-theme-pink-on-white-design.md`
- Modify: `docs/superpowers/specs/2026-07-01-childcare-management-design.md`

- [ ] **Step 1:** Flip the theme spec status → `implemented 2026-09-07`.
- [ ] **Step 2:** In the main design spec's look-and-feel / `app_theme.dart` note, update the description from "soft-pink seed + tinted (pink) top/bottom bars" to: white base surface, soft pink (`#FDB0C0`) as the accent (`colorScheme.primary`, `onPrimary` = dark rose `#5A2A33`), bars carry a faint pink wash (`AppTheme.barTint`), the bottom-nav selection pill is the pink accent, role chips get a pink tint via `chipTheme`. Pointer to `2026-09-07-theme-pink-on-white-design.md`.
- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-09-07-theme-pink-on-white-design.md docs/superpowers/specs/2026-07-01-childcare-management-design.md
git commit -m "docs: record the pink-on-white theme"
```

---

## Done when

- `AppTheme.light`: `scaffoldBackgroundColor` and `colorScheme.surface` are `Colors.white`; `colorScheme.primary == AppTheme.seed`; both bar themes use `AppTheme.barTint`; nav indicator is the pink accent.
- The bottom nav shows a soft-pink selection pill on a nearly-white bar with `onAccent` text.
- `FilledButton`s, focused text-field borders, and the attendance section headers are soft pink; the rest of the app is white/neutral.
- `flutter analyze` clean, full suite green (report the count).
- The user has eyeballed the running app (both bars, a FilledButton screen, a focused field, the attendance dividers, a role chip).
