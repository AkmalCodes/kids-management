# Theme — soft pink on white — design

**Date:** 2026-09-07
**Status:** approved, not yet implemented

## Problem

The app's light theme currently reads as **pink-forward**: the top bar and
the floating bottom nav are filled with `colorScheme.primaryContainer` (a
mid-soft pink), so pink is the dominant colour and white is only the content
area. The wanted look is the inverse — **white is the main surface, soft pink
is an accent** used for highlights (selected nav tab, primary buttons, focus
rings, small header/chip/badge tints).

## Goals

- Pure white (`#FFFFFF`) is the scaffold/background everywhere.
- The top bar and bottom nav are no longer pink-filled; they carry only a
  **faint** pink wash so they still frame the content.
- Soft pink (`#FDB0C0`, the existing seed) is the highlight colour for:
  selected bottom-nav pill, `FilledButton` / primary actions, focused input
  borders + selection controls (checkbox/switch/slider), and small accent
  surfaces (attendance section dividers, role chips, status-ish badges).
- One source of truth: `lib/core/theme/app_theme.dart`. Anything that reads a
  colour from `Theme.of(context).colorScheme` picks up the change; the few
  widgets that hard-code a scheme colour are audited.

## Non-goals

- A dark theme. The app is light-only today; this does not add one.
- Changing the seed colour, the font (Nunito), the corner radius, button
  padding, or any layout.
- Restyling the schedule event-colour palette
  (`lib/core/constants/schedule_colors.dart`) — those are user-chosen event
  tags, unrelated to the app chrome.
- The child-attendance status badges' green/red/amber (semantic, not brand).

## Colour tokens

Added to `AppTheme`:

```dart
static const seed = Color(0xFFFDB0C0);       // soft pink — the accent
static const onAccent = Color(0xFF5A2A33);   // dark rose, for text/icons ON soft pink
static const barTint = Color(0xFFFFF2F5);    // the faint wash on bars
```

(`seedColor` stays as-is for `ColorScheme.fromSeed`; `seed` is the same value
re-exported under a clearer name for direct use. Keep one constant, rename in
place — do not have two.)

The `ColorScheme` is `ColorScheme.fromSeed(seedColor: seed)` **then
`.copyWith(...)`**:

| token | value | why |
|---|---|---|
| `surface` | `Colors.white` | the base |
| `primary` | `seed` (`#FDB0C0`) | so `FilledButton`, focus rings, `SwitchListTile` etc. use the literal soft pink, not the M3 dark-rose the raw seed produces at tone 40 |
| `onPrimary` | `onAccent` | `#FDB0C0` fails contrast with white; dark rose passes |
| everything else | untouched | derived tones stay for `surfaceContainerHighest` (input fill), `onSurfaceVariant` (secondary text), `error`, etc. |

`scaffoldBackgroundColor` → `Colors.white` (was `colorScheme.surface`, now
redundant but keep it explicit).

## Bars

`appBarTheme` and `navigationBarTheme` in `app_theme.dart`, and the
hand-rolled `AppBottomNav`:

- App bar `backgroundColor` → `AppTheme.barTint` (was `primaryContainer`).
  `foregroundColor` → `colorScheme.onSurface` (was `onPrimaryContainer`).
  Keep the rounded bottom, `elevation: 0`, slim `toolbarHeight`.
- `navigationBarTheme.backgroundColor` → `barTint`. `indicatorColor` →
  `colorScheme.primary` (the soft pink pill — was `surface`, a white pill on
  pink; now inverted).
- **`AppBottomNav`** (`lib/shared/widgets/app_bottom_nav.dart`) hard-codes
  `scheme.primaryContainer` for the bar `Material` and `scheme.surface` for
  the sliding highlight. Change to: bar `Material` → `AppTheme.barTint`;
  sliding highlight `DecoratedBox` colour → `scheme.primary`. `_NavItem`'s
  `fg`: selected → `AppTheme.onAccent` (text/icon on the pink pill),
  unselected → `scheme.onSurfaceVariant`. The soft shadow that lifts the bar
  off the white body stays (it matters more now that the bar is nearly white).

## Other hard-coded scheme colours (audit)

Grep for `primaryContainer` / `colorScheme.primary` outside `app_theme.dart`:

- `lib/features/teacher/widgets/attendance_grid_tile.dart:~85` —
  `colors.primaryContainer` is the **child-photo placeholder** background
  (behind the person icon when there's no photo). With `primaryContainer`
  unchanged (only `primary`/`surface` are `copyWith`-overridden) this stays a
  soft pink tint, which is fine as a placeholder. **No change**, but confirm
  it still looks deliberate against the new white grid.
- `lib/features/auth/login_screen.dart:~90` — `colorScheme.primary` on
  (likely) an icon/accent. Now the literal soft pink; check contrast where it
  sits. Adjust to `onSurface` only if it's text on white that becomes hard to
  read.
- `lib/shared/widgets/app_loader.dart:~58` — spinner colour
  `colorScheme.primary`. Soft pink spinner on white — acceptable; leave.
- The attendance `_SectionDivider` (Piece C,
  `mark_attendance_screen.dart`) uses `onSurfaceVariant` for its label and
  `Divider()` default for the lines — give the label
  `colorScheme.primary` so the section headers read as the wanted pink
  accent. (This is the "section headers" highlight the design calls for.)
- Role `Chip`s (`person_detail_screen.dart`, `profile_screen.dart`) and any
  status-ish chip: set a soft-pink container via
  `Chip(backgroundColor: colorScheme.primary.withValues(alpha: 0.15))` or a
  theme-level `chipTheme` — prefer a `chipTheme` in `app_theme.dart` so it's
  one place.

## Testing

- The app has **no theme test file today** and this change is almost entirely
  declarative. Add a small `test/core/theme/app_theme_test.dart` asserting the
  load-bearing facts: `AppTheme.light.scaffoldBackgroundColor ==
  Colors.white`; `colorScheme.surface == Colors.white`; `colorScheme.primary
  == AppTheme.seed`; `appBarTheme.backgroundColor == AppTheme.barTint`.
- `AppBottomNav` already has a test
  (`test/.../app_bottom_nav_test.dart` — confirm) — update any colour
  assertion it makes; add one that the selected pill is `scheme.primary`.
- Existing widget tests that assert a specific colour (search the test tree
  for `primaryContainer`, `onPrimaryContainer`) get updated to the new token.
- Run the full suite; report the real count. A handful of goldens/colour
  assertions will need re-baselining — list them in the plan as they surface.

## Rollout note

Purely visual. Worth the user running the app after to eyeball: the two bars,
a screen with a `FilledButton`, a focused text field, the attendance section
dividers, and a role chip.

## Open questions

None.
