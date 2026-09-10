-- Recurrence options reduced to once / daily / weekly (monthly + annually
-- removed; a single-occurrence "once" added). See
-- docs/superpowers/specs/2026-09-10-schedule-ui-fixes-design.md.
--
-- No data conversion: confirmed there are no monthly/annually rows.
-- Run once, by hand, in the Supabase SQL editor.

-- 1. Confirm the current constraint's name (expect 'schedule_entries_recurrence_check'):
--    select conname from pg_constraint
--    where conrelid = 'schedule_entries'::regclass and contype = 'c';

ALTER TABLE schedule_entries DROP CONSTRAINT IF EXISTS schedule_entries_recurrence_check;
ALTER TABLE schedule_entries
  ADD CONSTRAINT schedule_entries_recurrence_check
  CHECK (recurrence IN ('once', 'daily', 'weekly'));
