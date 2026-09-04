# Teacher attendance grid — design

**Date:** 2026-09-01
**Status:** approved, not yet implemented
**Screens:** `MarkAttendanceScreen` (rework), `ChildAttendanceDetailScreen` (new)

## Problem

The teacher's Attendance tab is a `ListView` of cards, one per child, where
tapping a card expands it in place (`_expandedChildId`, one at a time). Marking
a register means scrolling a single-column list and expanding each child in
turn. There is no way to see at a glance who has been marked and who has not.

`mark_attendance_screen.dart` is 517 lines and holds the roster, the search, the
expand/collapse state, the status buttons, both photo pickers, and the notes
field. Moving the per-child detail into its own screen shrinks it to what it
should be: a roster and its interactions.

## Goals

- See the whole class at once, with each child's status readable at a glance.
- Mark a child present or absent without leaving the grid.
- Keep everything the expanded card can do today — status, check-in photo,
  belongings photo, notes — reachable in one tap.
- Surface allergies without requiring a tap.

## Non-goals (deliberately deferred, each with a reason)

- **Teachers in the grid, with their own attendance.** The `attendance` table is
  children-only: `child_id UUID REFERENCES children(id) NOT NULL` with
  `UNIQUE (child_id, date)`. Recording staff attendance needs a new table, RLS
  encoding "a teacher marks only themselves, a director marks anyone", a model,
  controller methods and tests — comparable in size to this whole feature. Its
  own cycle.
- **Parent contact details on the detail screen.** Wanted, and agreed as the
  next piece of work. Currently impossible: `profiles_select` allows
  `id = auth.uid() OR director`, and `children_parents_select` allows
  `parent_id = auth.uid() OR director`, so a teacher can read neither the
  parent's profile nor the link row. Requires a new RLS policy plus a guardian
  model (guardian type, one father / one mother per child), phone capture during
  parent onboarding, and call/WhatsApp actions. Specced separately.
- **Combining the director's Attendance and People tabs.** Raised, not designed.
  Those tabs do different jobs — daily marking versus management — and merging
  them is an information-architecture change, not a layout one.
- **A grid month view for Schedules.** Unrelated to attendance.

## The grid

Replaces `ListView.builder` and `_childCard` in `MarkAttendanceScreen`. Children
only, ordered as `fetchForTeacher` returns them (by name).

```
   ╭──────╮  ╭──────╮  ╭──────╮  ╭──────╮
   │      │  │      │  │      │  │      │
   │  img │  │  img │  │  img │  │  img │
   │    ✓ │  │    ✕ │  │    ? │  │    ✓ │
   ╰──────╯  ╰──────╯  ╰──────╯  ╰──────╯
    Amir      Bella     Chong     Dini
```

Four tiles per row. Each tile is a square avatar with rounded corners and a
**translucent pink border** — `colorScheme.primary` at low opacity, so it reads
as part of the app's palette rather than a hard outline. The child's name sits
beneath as a shortened label (`shortLabelName`: first word plus last initial,
e.g. "Ammar H.") on a single line, so a long name can't wrap and distort the
avatar size.

A **status badge** sits inset from the bottom-right corner, with padding so it
floats over the avatar rather than touching its edge:

| Status | Badge |
| --- | --- |
| present | green check |
| absent | red cancel |
| not yet marked | amber question mark |

The amber state is the operationally important one: it is how a teacher sees who
is still outstanding. It is a *rendering* of "no attendance row exists for this
child today", not a stored status — `AttendanceStatus` gains no new value.

`AttendanceStatus` also has `late` and `excused`, which the UI has never offered
(`_statusChoices` is `[present, absent]`). Records carrying them are possible in
principle; the grid renders any status outside present/absent with the amber
badge rather than inventing an icon for a state the UI cannot set.

Search and the fixed `_todayDate` behaviour are unchanged. The existing comment
on `_todayDate` explains why it is captured once — a mark made near midnight must
not silently target a different day than the one on screen — and that reasoning
still holds.

## Interactions

- **Tap** → opens `ChildAttendanceDetailScreen`.
- **Long-press** → a menu: *Open details*, *Mark present*, *Mark absent*.

Long-press marking calls the existing `_setStatus`, which applies the row
returned by the write directly to the loaded roster instead of re-fetching. The
badge therefore updates immediately; the comment in `_applyUpdate` records that
the round trip was what made status changes visibly lag before.

Tap is the discoverable path and does not mutate anything. Long-press is the
shortcut for the common case. Nothing is reachable *only* by long-press, so the
undiscoverability of that gesture costs nothing.

## `ChildAttendanceDetailScreen`

New file: `lib/features/teacher/screens/child_attendance_detail_screen.dart`.

```
←  Amir Hakim
──────────────────────────────
 avatar   Amir Hakim
          Sunflower
          ⚠ Peanuts               ← only when allergies is non-empty
──────────────────────────────
 Today · Mon 1 Sept
   Status    (Present) (Absent)
   Check-in ▢   Belongings ▢
   Notes  ┌───────────────┐
──────────────────────────────
 ▸ Child details               ← collapsed by default
     Date of birth · Age
     Class
     Allergies
     Notes
```

**Identity strip.** Avatar, name, class. An allergy chip appears whenever
`child.allergies` is non-empty — always visible, never behind the collapse.
Allergy information can be needed immediately, and a teacher should not have to
know to look for it. The same text also appears inside the collapsible, so the
child-details section stays complete on its own.

**Daily section.** Exactly what the expanded card does today: the two status
choices, both photo slots, and the notes field. Same widgets
(`_photoSlotWithLabel`, `SignedPhotoThumbnail`, `AttendanceStatusChip`) and the
same controller calls, moved rather than rewritten.

**Child details.** Collapsed by default, read-only: date of birth with computed
age, class, allergies, notes. Read-only is not a simplification — RLS restricts
`children` writes to directors, so an edit affordance here could only produce a
failure.

Every field it shows is already in memory. `ChildController.fetchForTeacher`
issues `.select()`, so the roster load already carries `dob`, `className`,
`allergies`, `notes` and `avatarPath`. The collapsible needs no query and no
permission it does not already have. It also cannot leak parent contacts,
because parents are not part of the `Child` model.

## What is removed

`_childCard`, `_expandedChildId`, `_toggleExpanded`, and the expanded-card
branch. The photo-slot helpers, `_setStatus`, `_applyUpdate` and the notes
handling move to the detail screen. `MarkAttendanceScreen` keeps the roster
load, the search, the grid, and the long-press actions.

## Testing

`test/features/teacher/screens/mark_attendance_screen_test.dart` exists and
currently asserts list-and-expand behaviour; those assertions are rewritten
against the grid rather than deleted.

**Grid:**
- renders one tile per child returned by the roster
- a child with a `present` record shows the green badge; `absent` shows red; a
  child with no record for today shows amber
- long-press opens the menu; choosing *Mark present* calls the controller once
  and the badge becomes green without a re-fetch
- tap pushes the detail screen
- search filters the tiles

**Detail screen (new test file):**
- shows the allergy chip when allergies are non-empty, and omits it when empty
- child details are collapsed on first build and expand on tap
- setting a status calls `markAttendance` with the child, date and status
- notes and both photo slots behave as they did in the card, so the tests move
  across with the widgets

The full suite is 208 tests and must stay green.

## Open questions

None. Teacher attendance, parent contacts, the director tab merge and the
schedule month view are all listed under non-goals with their reasons, and each
is a separate piece of work.
