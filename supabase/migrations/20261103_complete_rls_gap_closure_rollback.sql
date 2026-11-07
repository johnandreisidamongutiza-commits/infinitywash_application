-- ====================================================================
-- Rollback: 20261103_complete_rls_gap_closure_rollback.sql
-- Description: Reverts the policies added in 20261103_complete_rls_gap_closure.sql
-- ====================================================================

DROP POLICY IF EXISTS "rfid_cards_select_all" ON public.rfid_loyalty_cards;
DROP POLICY IF EXISTS "rfid_cards_manage_staff" ON public.rfid_loyalty_cards;
DROP POLICY IF EXISTS "rfid_cards_update_rider" ON public.rfid_loyalty_cards;
DROP POLICY IF EXISTS "rfid_cards_update_customer" ON public.rfid_loyalty_cards;

DROP POLICY IF EXISTS "loyalty_history_select_all" ON public.loyalty_points_history;
DROP POLICY IF EXISTS "loyalty_history_manage_staff" ON public.loyalty_points_history;
DROP POLICY IF EXISTS "loyalty_history_insert_rider" ON public.loyalty_points_history;
DROP POLICY IF EXISTS "loyalty_history_insert_customer" ON public.loyalty_points_history;

