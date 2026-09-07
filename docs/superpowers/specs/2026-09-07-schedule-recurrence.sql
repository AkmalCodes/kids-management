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
