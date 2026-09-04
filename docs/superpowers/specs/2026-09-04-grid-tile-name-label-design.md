# Grid tile name label — design

**Date:** 2026-09-04
**Status:** approved, not yet implemented

## Problem

`AttendanceGridTile` renders the child's full name under the avatar with
`maxLines: 2`. The name `Text` sits *outside* the `Expanded` that wraps the
avatar, so when a name wraps to two lines it consumes extra vertical space and
the `Expanded` avatar shrinks — for that one tile. The result is a grid whose
avatars are visibly different sizes depending on how long each child's name is.
That was never intended.

This is piece **A** of a three-part change (A: this; B: a co-teacher data
model; C: a two-grid teacher attendance page that reuses this tile). A is
independent of B and C and ships first.

## Goals

- Every avatar in the grid is the same size, regardless of name length.
- A name never wraps and never pushes the avatar around.
- Long names degrade to something short and readable, not a truncated middle
  of a full name.

## Non-goals

- The two-grid attendance page (piece C) and the co-teacher model (piece B).
- Changing the grid delegate (`crossAxisCount: 4`, `childAspectRatio: 0.72`)
  or anything about the badge, the photo, or the tap/long-press behaviour.
- Changing search. `MarkAttendanceScreen`'s search still matches on the full
  `child.name`; only the *displayed* label shortens.

## Name label — `shortLabelName(String fullName)`

New pure function, `lib/shared/util/name_display.dart` — its own file beside
`date_display.dart`, so it is unit-testable and piece C's Teachers grid can
reuse it for teacher names.

Rules, applied after `fullName.trim()` and splitting on runs of whitespace
(empty segments dropped):

| parts | result | example |
|-------|--------|---------|
| 0 | `''` | `"   "` → `""` |
| 1 | `parts[0]` | `"Alice"` → `"Alice"` |
| 2 or more | `"${parts.first} ${parts.last[0].toUpperCase()}."` | `"Ammar Ali"` → `"Ammar A."`; `"Muhammad Aariz Danish bin Abdul Rahman"` → `"Muhammad R."`; `"nur aisyah"` → `"nur A."` |

The first word keeps its own casing; only the trailing initial is forced
upper-case. A pathologically long single first name is still clipped by the
tile (`"Bartholomew…"`) — see below — but that is the rare case, not the
common one.

## Tile layout — `AttendanceGridTile`

Two changes inside `build`, nothing else:

1. The name `Text` renders `shortLabelName(child.name)` instead of
   `child.name`, with `maxLines: 1` (was 2). `overflow: TextOverflow.ellipsis`
   and `textAlign: TextAlign.center` stay.
2. The name slot is always exactly one line tall, even when the label is
   empty. `maxLines: 1` already fixes the height for any non-empty label at
   the current text scale; the only gap is a genuinely empty label (a Child
   with a blank name — not a real scenario today, names are required, but
   cheap to be safe about), which a
   `Text` paints at zero height. Cover that by rendering a non-breaking space
   (`' '`) when `shortLabelName` returns `''`. No hard-coded pixel
   height and no manual line-height math — text scaling still flows through
   `Text` itself, which is the property the existing "does not overflow at
   large accessibility text scale" test guards.

With the name slot fixed, the `Expanded` above it hands the `AspectRatio(1)`
avatar an identical box on every tile.

The existing structural comment above the `Expanded` (which currently explains
why the avatar is `Expanded` rather than a fixed `AspectRatio` — "the name
takes its natural height first") is updated: the name no longer takes natural
height, it takes exactly one line, and the avatar absorbs the fixed remainder.

## Testing

- **New** `test/shared/util/name_display_test.dart` — `shortLabelName` for:
  one word; two words; three-plus words; empty / whitespace-only; leading and
  internal extra whitespace; a name whose last word is lower-case (initial
  comes back upper-case); a single-character last word.
- **`test/features/teacher/widgets/attendance_grid_tile_test.dart`** — add:
  - a tile built with `name: 'Ammar Ali Hassan'` renders `find.text('Ammar H.')`.
  - the avatar's rendered size is equal between a short-name tile
    (`'Alice'`) and a long-name tile
    (`'Muhammad Aariz Danish bin Abdul Rahman'`) — the actual regression
    guard for this change. Compare the `Size` of the `AspectRatio`
    descendant (or the photo `ClipRRect`) via `tester.getSize`.
  - The existing `'shows the child name'` (`'Alice'`, a single word, so the
    label is unchanged), the two overflow tests, the textScale test, and the
    `CircleAvatar` test all stay as-is and must remain green.
- **`test/features/teacher/screens/mark_attendance_screen_test.dart`** —
  expected to need no change: its fixtures are `'Alice'` / `'Bob'` (single
  words, label unchanged) and the search test filters on the full name. Run
  it to confirm; if a `find.text` on a tile label breaks, update that one
  assertion to the shortened label.
- Full Flutter suite stays green.

## Docs

- `docs/superpowers/specs/2026-07-01-childcare-management-design.md` — wherever
  the attendance grid tile is described, note that the tile shows a shortened
  label (`First L.`), not the full name.
- `docs/superpowers/specs/2026-09-01-teacher-attendance-grid-design.md` — one
  line recording that the name label was changed to `shortLabelName` to keep
  avatars uniform.

## Open questions

None.
