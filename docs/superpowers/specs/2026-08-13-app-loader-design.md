# Themed loading indicator (`AppLoader`)

**Date:** 2026-08-13
**Status:** Approved, implementing

## Problem

Every loading state in the app (`AuthGate`/`RoleRouter` during the login → dashboard
transition, and every `FutureBuilder`/`AsyncValue.when` loading branch across the
feature screens) renders a bare `CircularProgressIndicator()` — default Material
colors, no relation to the app's pink theme, appears/disappears with no transition.
The login → dashboard gap in particular can take a noticeable moment (auth stream
emission + profile fetch), so the plain spinner reads as dead time rather than
something happening.

## Design

### `AppLoader` widget

New file: `lib/shared/widgets/app_loader.dart`.

```dart
class AppLoader extends StatefulWidget {
  const AppLoader({super.key, this.size = 36, this.delayed = true});
  final double size;
  final bool delayed;
}
```

- **Themed:** `CircularProgressIndicator` colored from
  `Theme.of(context).colorScheme.primary` (seed pink), `strokeWidth` scaled to `size`
  instead of Material's default gray/adaptive color.
- **Entrance animation:** starts at `opacity: 0, scale: 0.8`, animates to
  `opacity: 1, scale: 1.0` over ~200ms (`AnimatedOpacity` + `AnimatedScale`) once
  revealed.
- **Debounce (`delayed: true`, default):** invisible for the first 250ms after
  mounting (`Future.delayed` + `setState`), then plays the entrance animation. A
  load that finishes within 250ms shows nothing at all — no flash for fast screens.
  A slower load gets the loader with a pop-in instead of an abrupt appear.
- **`delayed: false`:** skips the wait, animates in immediately. For button-press
  spinners, where instant feedback on tap matters more than avoiding flash.

### Rollout

44 `CircularProgressIndicator` occurrences across 32 files, two call-site shapes:

- **Page/section loaders** (majority — `Center(child: CircularProgressIndicator())`
  inside a `FutureBuilder`/`AsyncValue.when` loading branch): swap to
  `Center(child: AppLoader())` (defaults: 36px, delayed).
- **Inline button spinners** (a handful, e.g. `login_screen.dart`'s sign-in button —
  `SizedBox(20x20, CircularProgressIndicator(strokeWidth: 2))` while `_loading`):
  swap to `AppLoader(size: 20, delayed: false)`.

Mechanical widget swap per occurrence, no logic/state changes.

### Testing

- Widget test for `AppLoader`: invisible immediately after pump; visible after
  pumping past 250ms with `delayed: true`; immediately visible with `delayed:
  false`.
- Existing screen tests asserting `find.byType(CircularProgressIndicator)` during
  loading states updated to `find.byType(AppLoader)`.

## Out of scope

- No new package dependency (no Lottie/Rive) — pure Flutter animation primitives.
- No app-wide dark theme handling beyond what `Theme.of(context).colorScheme`
  already resolves.
- No change to *when* loading states trigger, only how they render.
