-- ====================================================================
-- Rollback: 20261103_rider_locations_rls_rollback.sql
-- Description: Reverts the policies created by
--              20261103_rider_locations_rls.sql back to the original
--              wildcard policy from 20261031.
--              Does NOT drop the table (it may contain live data).
-- Date: 2026-11-03
-- ====================================================================

-- Drop the new policies
DROP POLICY IF EXISTS "rider_locations_select_authenticated" ON public.rider_locations;
DROP POLICY IF EXISTS "rider_locations_upsert_rider" ON public.rider_locations;

-- Restore the original wildcard policy
CREATE POLICY "rider_locations_all"
  ON public.rider_locations FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

