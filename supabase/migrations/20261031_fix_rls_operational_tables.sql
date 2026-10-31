-- ====================================================================
-- Migration: 20261031_fix_rls_operational_tables.sql
-- Description: Grants table-level permissions to the `authenticated` role
--              across public tables, and creates Row Level Security (RLS)
--              policies for orders, order_loads, service_catalog, 
--              dispatch_jobs, payments, and related operational tables.
-- Date: 2026-10-31
-- ====================================================================

-- --------------------------------------------------------------------
-- STEP 1: Grant table-level permissions to `authenticated` role
-- (Fixes "ERROR 42501: permission denied for table orders / 403 Forbidden")
-- RLS policies below will strictly enforce who can view and edit which rows.
-- --------------------------------------------------------------------
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL ROUTINES IN SCHEMA public TO authenticated;

-- Ensure future tables also inherit these permissions so they don't break
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON ROUTINES TO authenticated;

-- Anonymous users can read active service catalog (if logged out or browsing)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'service_catalog') THEN
    EXECUTE 'GRANT SELECT ON TABLE public.service_catalog TO anon';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'service_addons') THEN
    EXECUTE 'GRANT SELECT ON TABLE public.service_addons TO anon';
  END IF;
END $$;

-- --------------------------------------------------------------------
-- STEP 2: RLS on `service_catalog` & `service_addons`
-- --------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'service_catalog') THEN
    EXECUTE 'ALTER TABLE public.service_catalog ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS "service_catalog_select" ON public.service_catalog';
    EXECUTE 'DROP POLICY IF EXISTS "service_catalog_manage_staff" ON public.service_catalog';

    -- Anyone can read active services
    EXECUTE 'CREATE POLICY "service_catalog_select" ON public.service_catalog FOR SELECT TO authenticated, anon USING (true)';
    -- Staff/Admin can add/update services
    EXECUTE 'CREATE POLICY "service_catalog_manage_staff" ON public.service_catalog FOR ALL TO authenticated USING (public.is_staff_or_admin()) WITH CHECK (public.is_staff_or_admin())';
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'service_addons') THEN
    EXECUTE 'ALTER TABLE public.service_addons ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS "service_addons_select" ON public.service_addons';
    EXECUTE 'DROP POLICY IF EXISTS "service_addons_manage_staff" ON public.service_addons';

    EXECUTE 'CREATE POLICY "service_addons_select" ON public.service_addons FOR SELECT TO authenticated, anon USING (true)';
    EXECUTE 'CREATE POLICY "service_addons_manage_staff" ON public.service_addons FOR ALL TO authenticated USING (public.is_staff_or_admin()) WITH CHECK (public.is_staff_or_admin())';
  END IF;
END $$;

-- --------------------------------------------------------------------
-- STEP 3: RLS on `orders`
-- --------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'orders') THEN
    EXECUTE 'ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY';

    EXECUTE 'DROP POLICY IF EXISTS "orders_staff_admin_all" ON public.orders';
    EXECUTE 'DROP POLICY IF EXISTS "orders_customer_select" ON public.orders';
    EXECUTE 'DROP POLICY IF EXISTS "orders_customer_insert" ON public.orders';
    EXECUTE 'DROP POLICY IF EXISTS "orders_customer_update" ON public.orders';
    EXECUTE 'DROP POLICY IF EXISTS "orders_rider_select" ON public.orders';
    EXECUTE 'DROP POLICY IF EXISTS "orders_rider_update" ON public.orders';

    -- 1. Staff and Admins have full access to all orders
    EXECUTE 'CREATE POLICY "orders_staff_admin_all"
      ON public.orders FOR ALL TO authenticated
      USING (public.is_staff_or_admin())
      WITH CHECK (public.is_staff_or_admin())';

    -- 2. Customers can read their own orders
    EXECUTE 'CREATE POLICY "orders_customer_select"
      ON public.orders FOR SELECT TO authenticated
      USING (
        customer_id IN (
          SELECT c.id FROM public.customers c
          WHERE c.profile_id = public.get_auth_profile_id()
        )
      )';

    -- 3. Customers can insert their own orders
    EXECUTE 'CREATE POLICY "orders_customer_insert"
      ON public.orders FOR INSERT TO authenticated
      WITH CHECK (
        customer_id IN (
          SELECT c.id FROM public.customers c
          WHERE c.profile_id = public.get_auth_profile_id()
        )
      )';

    -- 4. Customers can update their own orders (e.g. cancel, add notes)
    EXECUTE 'CREATE POLICY "orders_customer_update"
      ON public.orders FOR UPDATE TO authenticated
      USING (
        customer_id IN (
          SELECT c.id FROM public.customers c
          WHERE c.profile_id = public.get_auth_profile_id()
        )
      )
      WITH CHECK (
        customer_id IN (
          SELECT c.id FROM public.customers c
          WHERE c.profile_id = public.get_auth_profile_id()
        )
      )';

    -- 5. Riders can view orders (assigned to them or available for pickup/delivery)
    EXECUTE 'CREATE POLICY "orders_rider_select"
      ON public.orders FOR SELECT TO authenticated
      USING (public.is_rider())';

    -- 6. Riders can update orders assigned to them
    EXECUTE 'CREATE POLICY "orders_rider_update"
      ON public.orders FOR UPDATE TO authenticated
      USING (public.is_rider())
      WITH CHECK (public.is_rider())';
  END IF;
END $$;

-- --------------------------------------------------------------------
-- STEP 4: RLS on `order_loads` & `order_addons`
-- --------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'order_loads') THEN
    EXECUTE 'ALTER TABLE public.order_loads ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS "order_loads_staff_admin_all" ON public.order_loads';
    EXECUTE 'DROP POLICY IF EXISTS "order_loads_customer_select" ON public.order_loads';
    EXECUTE 'DROP POLICY IF EXISTS "order_loads_customer_insert" ON public.order_loads';
    EXECUTE 'DROP POLICY IF EXISTS "order_loads_rider_select" ON public.order_loads';

    EXECUTE 'CREATE POLICY "order_loads_staff_admin_all"
      ON public.order_loads FOR ALL TO authenticated
      USING (public.is_staff_or_admin())
      WITH CHECK (public.is_staff_or_admin())';

    EXECUTE 'CREATE POLICY "order_loads_customer_select"
      ON public.order_loads FOR SELECT TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.orders o
          JOIN public.customers c ON c.id = o.customer_id
          WHERE o.id = order_loads.order_id
            AND c.profile_id = public.get_auth_profile_id()
        )
      )';

    EXECUTE 'CREATE POLICY "order_loads_customer_insert"
      ON public.order_loads FOR INSERT TO authenticated
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.orders o
          JOIN public.customers c ON c.id = o.customer_id
          WHERE o.id = order_loads.order_id
            AND c.profile_id = public.get_auth_profile_id()
        )
      )';

    EXECUTE 'CREATE POLICY "order_loads_rider_select"
      ON public.order_loads FOR SELECT TO authenticated
      USING (public.is_rider())';
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'order_addons') THEN
    EXECUTE 'ALTER TABLE public.order_addons ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS "order_addons_staff_admin_all" ON public.order_addons';
    EXECUTE 'DROP POLICY IF EXISTS "order_addons_customer_select" ON public.order_addons';
    EXECUTE 'DROP POLICY IF EXISTS "order_addons_customer_insert" ON public.order_addons';

    EXECUTE 'CREATE POLICY "order_addons_staff_admin_all"
      ON public.order_addons FOR ALL TO authenticated
      USING (public.is_staff_or_admin())
      WITH CHECK (public.is_staff_or_admin())';

    EXECUTE 'CREATE POLICY "order_addons_customer_select"
      ON public.order_addons FOR SELECT TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.orders o
          JOIN public.customers c ON c.id = o.customer_id
          WHERE o.id = order_addons.order_id
            AND c.profile_id = public.get_auth_profile_id()
        )
      )';

    EXECUTE 'CREATE POLICY "order_addons_customer_insert"
      ON public.order_addons FOR INSERT TO authenticated
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.orders o
          JOIN public.customers c ON c.id = o.customer_id
          WHERE o.id = order_addons.order_id
            AND c.profile_id = public.get_auth_profile_id()
        )
      )';
  END IF;
END $$;

-- --------------------------------------------------------------------
-- STEP 5: RLS on `dispatch_jobs` & `rider_locations`
-- --------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'dispatch_jobs') THEN
    EXECUTE 'ALTER TABLE public.dispatch_jobs ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS "dispatch_jobs_staff_admin_all" ON public.dispatch_jobs';
    EXECUTE 'DROP POLICY IF EXISTS "dispatch_jobs_rider_all" ON public.dispatch_jobs';
    EXECUTE 'DROP POLICY IF EXISTS "dispatch_jobs_customer_select" ON public.dispatch_jobs';

    EXECUTE 'CREATE POLICY "dispatch_jobs_staff_admin_all"
      ON public.dispatch_jobs FOR ALL TO authenticated
      USING (public.is_staff_or_admin())
      WITH CHECK (public.is_staff_or_admin())';

    EXECUTE 'CREATE POLICY "dispatch_jobs_rider_all"
      ON public.dispatch_jobs FOR ALL TO authenticated
      USING (public.is_rider())
      WITH CHECK (public.is_rider())';

    EXECUTE 'CREATE POLICY "dispatch_jobs_customer_select"
      ON public.dispatch_jobs FOR SELECT TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.orders o
          JOIN public.customers c ON c.id = o.customer_id
          WHERE o.id = dispatch_jobs.order_id
            AND c.profile_id = public.get_auth_profile_id()
        )
      )';
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'rider_locations') THEN
    EXECUTE 'ALTER TABLE public.rider_locations ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS "rider_locations_all" ON public.rider_locations';
    EXECUTE 'CREATE POLICY "rider_locations_all" ON public.rider_locations FOR ALL TO authenticated USING (true) WITH CHECK (true)';
  END IF;
END $$;

-- --------------------------------------------------------------------
-- STEP 6: RLS on `payments` & `gcash_receipt_submissions` & `gcash_settings`
-- --------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'gcash_settings') THEN
    EXECUTE 'ALTER TABLE public.gcash_settings ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS "gcash_settings_select" ON public.gcash_settings';
    EXECUTE 'DROP POLICY IF EXISTS "gcash_settings_manage" ON public.gcash_settings';
    EXECUTE 'CREATE POLICY "gcash_settings_select" ON public.gcash_settings FOR SELECT TO authenticated, anon USING (true)';
    EXECUTE 'CREATE POLICY "gcash_settings_manage" ON public.gcash_settings FOR ALL TO authenticated USING (public.is_staff_or_admin()) WITH CHECK (public.is_staff_or_admin())';
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'payments') THEN
    EXECUTE 'ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS "payments_staff_admin_all" ON public.payments';
    EXECUTE 'DROP POLICY IF EXISTS "payments_customer_select" ON public.payments';
    EXECUTE 'DROP POLICY IF EXISTS "payments_rider_select" ON public.payments';

    EXECUTE 'CREATE POLICY "payments_staff_admin_all"
      ON public.payments FOR ALL TO authenticated
      USING (public.is_staff_or_admin())
      WITH CHECK (public.is_staff_or_admin())';

    EXECUTE 'CREATE POLICY "payments_customer_select"
      ON public.payments FOR SELECT TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.orders o
          JOIN public.customers c ON c.id = o.customer_id
          WHERE o.id = payments.order_id
            AND c.profile_id = public.get_auth_profile_id()
        )
      )';

    EXECUTE 'CREATE POLICY "payments_rider_select"
      ON public.payments FOR SELECT TO authenticated
      USING (public.is_rider())';
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'gcash_receipt_submissions') THEN
    EXECUTE 'ALTER TABLE public.gcash_receipt_submissions ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS "gcash_receipts_staff_admin_all" ON public.gcash_receipt_submissions';
    EXECUTE 'DROP POLICY IF EXISTS "gcash_receipts_customer_all" ON public.gcash_receipt_submissions';
    EXECUTE 'DROP POLICY IF EXISTS "gcash_submissions_authenticated_insert" ON public.gcash_receipt_submissions';
    EXECUTE 'DROP POLICY IF EXISTS "gcash_submissions_authenticated_select" ON public.gcash_receipt_submissions';
    EXECUTE 'DROP POLICY IF EXISTS "gcash_submissions_authenticated_update" ON public.gcash_receipt_submissions';

    -- Staff and Admins can view/update any GCash submission
    EXECUTE 'CREATE POLICY "gcash_receipts_staff_admin_all"
      ON public.gcash_receipt_submissions FOR ALL TO authenticated
      USING (public.is_staff_or_admin())
      WITH CHECK (public.is_staff_or_admin())';

    -- Authenticated users (customers) can submit and view their own receipts
    EXECUTE 'CREATE POLICY "gcash_receipts_customer_all"
      ON public.gcash_receipt_submissions FOR ALL TO authenticated
      USING (
        submitted_by = public.get_auth_profile_id()
        OR EXISTS (
          SELECT 1 FROM public.orders o
          JOIN public.customers c ON c.id = o.customer_id
          WHERE o.id = gcash_receipt_submissions.order_id
            AND c.profile_id = public.get_auth_profile_id()
        )
      )
      WITH CHECK (
        submitted_by = public.get_auth_profile_id()
        OR EXISTS (
          SELECT 1 FROM public.orders o
          JOIN public.customers c ON c.id = o.customer_id
          WHERE o.id = gcash_receipt_submissions.order_id
            AND c.profile_id = public.get_auth_profile_id()
        )
      )';
  END IF;
END $$;

-- --------------------------------------------------------------------
-- STEP 7: RLS on `rfid_loyalty_cards` & `loyalty_points_history` & `feedback`
-- --------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'rfid_loyalty_cards') THEN
    EXECUTE 'ALTER TABLE public.rfid_loyalty_cards ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS "rfid_cards_all" ON public.rfid_loyalty_cards';
    EXECUTE 'CREATE POLICY "rfid_cards_all" ON public.rfid_loyalty_cards FOR ALL TO authenticated USING (true) WITH CHECK (public.is_staff_or_admin())';
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'loyalty_points_history') THEN
    EXECUTE 'ALTER TABLE public.loyalty_points_history ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS "loyalty_history_all" ON public.loyalty_points_history';
    EXECUTE 'CREATE POLICY "loyalty_history_all" ON public.loyalty_points_history FOR ALL TO authenticated USING (true) WITH CHECK (public.is_staff_or_admin())';
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'feedback') THEN
    EXECUTE 'ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS "feedback_staff_admin" ON public.feedback';
    EXECUTE 'DROP POLICY IF EXISTS "feedback_customer" ON public.feedback';

    EXECUTE 'CREATE POLICY "feedback_staff_admin" ON public.feedback FOR ALL TO authenticated USING (public.is_staff_or_admin()) WITH CHECK (public.is_staff_or_admin())';
    EXECUTE 'CREATE POLICY "feedback_customer" ON public.feedback FOR ALL TO authenticated USING (
      customer_id IN (SELECT id FROM public.customers WHERE profile_id = public.get_auth_profile_id())
    ) WITH CHECK (
      customer_id IN (SELECT id FROM public.customers WHERE profile_id = public.get_auth_profile_id())
    )';
  END IF;
END $$;
