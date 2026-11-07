-- ====================================================================
-- Migration: 20261103_complete_rls_gap_closure.sql
-- Description: Closes the final RLS edge cases discovered during system audit:
--              1. Allows Customers to link/unlink RFID loyalty cards.
--              2. Allows Riders to award loyalty points upon delivery completion.
--              3. Grants SELECT permissions on views (vw_rfid_loyalty_cards).
-- Date: 2026-11-03
-- ====================================================================

-- --------------------------------------------------------------------
-- STEP 1: Update RLS policies on `public.rfid_loyalty_cards`
-- --------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'rfid_loyalty_cards') THEN
    EXECUTE 'ALTER TABLE public.rfid_loyalty_cards ENABLE ROW LEVEL SECURITY';

    EXECUTE 'DROP POLICY IF EXISTS "rfid_cards_all" ON public.rfid_loyalty_cards';
    EXECUTE 'DROP POLICY IF EXISTS "rfid_cards_select_all" ON public.rfid_loyalty_cards';
    EXECUTE 'DROP POLICY IF EXISTS "rfid_cards_manage_staff" ON public.rfid_loyalty_cards';
    EXECUTE 'DROP POLICY IF EXISTS "rfid_cards_update_rider" ON public.rfid_loyalty_cards';
    EXECUTE 'DROP POLICY IF EXISTS "rfid_cards_update_customer" ON public.rfid_loyalty_cards';

    -- 1. Read: All authenticated users can read loyalty cards (needed for UID lookups, balance checks)
    EXECUTE 'CREATE POLICY "rfid_cards_select_all"
      ON public.rfid_loyalty_cards FOR SELECT TO authenticated
      USING (true)';

    -- 2. Staff & Admins: Full management (register, update, delete)
    EXECUTE 'CREATE POLICY "rfid_cards_manage_staff"
      ON public.rfid_loyalty_cards FOR ALL TO authenticated
      USING (public.is_staff_or_admin())
      WITH CHECK (public.is_staff_or_admin())';

    -- 3. Riders: Can update card points when completing delivery orders
    EXECUTE 'CREATE POLICY "rfid_cards_update_rider"
      ON public.rfid_loyalty_cards FOR UPDATE TO authenticated
      USING (public.is_rider())
      WITH CHECK (public.is_rider())';

    -- 4. Customers: Can link an unassigned card or unlink their currently assigned card
    EXECUTE 'CREATE POLICY "rfid_cards_update_customer"
      ON public.rfid_loyalty_cards FOR UPDATE TO authenticated
      USING (
        customer_id IS NULL 
        OR customer_id::text IN (
          SELECT id::text FROM public.customers WHERE profile_id = public.get_auth_profile_id()
        )
      )
      WITH CHECK (
        customer_id IS NULL 
        OR customer_id::text IN (
          SELECT id::text FROM public.customers WHERE profile_id = public.get_auth_profile_id()
        )
      )';
  END IF;
END $$;

-- --------------------------------------------------------------------
-- STEP 2: Update RLS policies on `public.loyalty_points_history`
-- --------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'loyalty_points_history') THEN
    EXECUTE 'ALTER TABLE public.loyalty_points_history ENABLE ROW LEVEL SECURITY';

    EXECUTE 'DROP POLICY IF EXISTS "loyalty_history_all" ON public.loyalty_points_history';
    EXECUTE 'DROP POLICY IF EXISTS "loyalty_history_select_all" ON public.loyalty_points_history';
    EXECUTE 'DROP POLICY IF EXISTS "loyalty_history_manage_staff" ON public.loyalty_points_history';
    EXECUTE 'DROP POLICY IF EXISTS "loyalty_history_insert_rider" ON public.loyalty_points_history';
    EXECUTE 'DROP POLICY IF EXISTS "loyalty_history_insert_customer" ON public.loyalty_points_history';

    -- 1. Read: Users can read their own points history; Staff can read all
    EXECUTE 'CREATE POLICY "loyalty_history_select_all"
      ON public.loyalty_points_history FOR SELECT TO authenticated
      USING (
        public.is_staff_or_admin()
        OR public.is_rider()
        OR customer_id::text = public.get_auth_profile_id()::text
        OR customer_id::text IN (
          SELECT id::text FROM public.customers WHERE profile_id = public.get_auth_profile_id()
        )
      )';

    -- 2. Staff & Admins: Full management
    EXECUTE 'CREATE POLICY "loyalty_history_manage_staff"
      ON public.loyalty_points_history FOR ALL TO authenticated
      USING (public.is_staff_or_admin())
      WITH CHECK (public.is_staff_or_admin())';

    -- 3. Riders: Can insert point history entries when completing a delivery order
    EXECUTE 'CREATE POLICY "loyalty_history_insert_rider"
      ON public.loyalty_points_history FOR INSERT TO authenticated
      WITH CHECK (public.is_rider())';

    -- 4. Customers: Can insert point history when claiming an order or redeeming
    EXECUTE 'CREATE POLICY "loyalty_history_insert_customer"
      ON public.loyalty_points_history FOR INSERT TO authenticated
      WITH CHECK (
        customer_id::text = public.get_auth_profile_id()::text
        OR customer_id::text IN (
          SELECT id::text FROM public.customers WHERE profile_id = public.get_auth_profile_id()
        )
      )';
  END IF;
END $$;

-- --------------------------------------------------------------------
-- STEP 3: Grant permissions on views
-- --------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.views WHERE table_schema = 'public' AND table_name = 'vw_rfid_loyalty_cards') THEN
    EXECUTE 'GRANT SELECT ON public.vw_rfid_loyalty_cards TO authenticated';
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.views WHERE table_schema = 'public' AND table_name = 'vw_rfid_scanner_status') THEN
    EXECUTE 'GRANT SELECT ON public.vw_rfid_scanner_status TO authenticated, anon';
  END IF;
END $$;
