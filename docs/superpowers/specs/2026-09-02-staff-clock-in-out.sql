-- Staff clock-in/out: teachers record the real time they started and finished
-- work, feeding HR and (later) payroll. See the design spec at
-- docs/superpowers/specs/2026-09-02-staff-clock-in-out-design.md for the full
-- reasoning, including why these are separate columns from created_at/updated_at
-- and why the CHECK constraint is worth having.
--
-- Additive only: extends the staff_attendance table from
-- docs/superpowers/plans/2026-09-02-staff-attendance-schema.md (which holds the
-- CREATE TABLE). Does not touch status, RLS, or anything else about that table.
--
-- Run this once, by hand, in the Supabase SQL editor (Project -> SQL Editor).
-- Re-running will error on "column already exists" rather than silently
-- reapplying, so you'll know if it already ran.

ALTER TABLE staff_attendance
  ADD COLUMN clock_in_at  TIMESTAMPTZ,
  ADD COLUMN clock_out_at TIMESTAMPTZ,
  ADD CONSTRAINT staff_attendance_clock_order
    CHECK (clock_out_at IS NULL OR (clock_in_at IS NOT NULL AND clock_out_at > clock_in_at));
