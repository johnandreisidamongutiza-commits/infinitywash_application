-- ====================================================================
-- Migration: 20261103_rider_locations_rls.sql
-- Description: Ensures the rider_locations table exists with proper
--              schema, grants, indexes, and secure RLS policies.
--              Replaces the unsafe wildcard "rider_locations_all" policy
--              from 20261031_fix_rls_operational_tables.sql (which may
--              have been skipped if the table didn't exist at migration
--              time) with explicit role-based policies:
--                - Riders: can upsert/delete their own location rows
--                - All authenticated: can read (for delivery tracking)
-- Date: 2026-11-03
-- ====================================================================

-- --------------------------------------------------------------------
-- STEP 1: Ensure table exists (idempotent)
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.rider_locations (
  rider_id uuid NOT NULL,
  dispatch_job_id uuid NULL,
  latitude numeric(10, 7) NOT NULL,
  longitude numeric(10, 7) NOT NULL,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT rider_locations_pkey PRIMARY KEY (rider_id),
  CONSTRAINT rider_locations_dispatch_job_id_fkey FOREIGN KEY (dispatch_job_id)
    REFERENCES public.dispatch_jobs (id) ON DELETE SET NULL,
  CONSTRAINT rider_locations_rider_id_fkey FOREIGN KEY (rider_id)
    REFERENCES public.employees (id) ON DELETE CASCADE
);

-- --------------------------------------------------------------------
-- STEP 2: Ensure indexes exist (idempotent)
-- --------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_rider_locations_dispatch_job_id
  ON public.rider_locations USING btree (dispatch_job_id);

CREATE INDEX IF NOT EXISTS idx_rider_locations_updated_at
  ON public.rider_locations USING btree (updated_at);

-- --------------------------------------------------------------------
-- STEP 3: Table-level grants
-- --------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.rider_locations TO authenticated;

-- --------------------------------------------------------------------
-- STEP 4: Enable RLS and replace policies
-- --------------------------------------------------------------------
ALTER TABLE public.rider_locations ENABLE ROW LEVEL SECURITY;

-- Drop old wildcard policy and any prior versions of the new policies
DROP POLICY IF EXISTS "rider_locations_all" ON public.rider_locations;
DROP POLICY IF EXISTS "rider_locations_select_authenticated" ON public.rider_locations;
DROP POLICY IF EXISTS "rider_locations_upsert_rider" ON public.rider_locations;

-- 1. Read: All authenticated users can view rider locations
--    (Customers need this for live delivery tracking maps;
--     Staff/Admin need it for operational dashboards)
CREATE POLICY "rider_locations_select_authenticated"
  ON public.rider_locations FOR SELECT TO authenticated
  USING (true);

-- 2. Write: Only Riders and Staff/Admin can insert, update, or delete
--    location rows (prevents customers from spoofing coordinates)
CREATE POLICY "rider_locations_upsert_rider"
  ON public.rider_locations FOR ALL TO authenticated
  USING (public.is_rider() OR public.is_staff_or_admin())
  WITH CHECK (public.is_rider() OR public.is_staff_or_admin());

