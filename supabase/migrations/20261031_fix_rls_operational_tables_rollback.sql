-- ====================================================================
-- Rollback: 20261031_fix_rls_operational_tables_rollback.sql
-- Description: Reverts the policies added in 20261031_fix_rls_operational_tables.sql
-- ====================================================================

DROP POLICY IF EXISTS "service_catalog_select" ON public.service_catalog;
DROP POLICY IF EXISTS "service_catalog_manage_staff" ON public.service_catalog;

DROP POLICY IF EXISTS "service_addons_select" ON public.service_addons;
DROP POLICY IF EXISTS "service_addons_manage_staff" ON public.service_addons;

DROP POLICY IF EXISTS "orders_staff_admin_all" ON public.orders;
DROP POLICY IF EXISTS "orders_customer_select" ON public.orders;
DROP POLICY IF EXISTS "orders_customer_insert" ON public.orders;
DROP POLICY IF EXISTS "orders_customer_update" ON public.orders;
DROP POLICY IF EXISTS "orders_rider_select" ON public.orders;
DROP POLICY IF EXISTS "orders_rider_update" ON public.orders;

DROP POLICY IF EXISTS "order_loads_staff_admin_all" ON public.order_loads;
DROP POLICY IF EXISTS "order_loads_customer_select" ON public.order_loads;
DROP POLICY IF EXISTS "order_loads_customer_insert" ON public.order_loads;
DROP POLICY IF EXISTS "order_loads_rider_select" ON public.order_loads;

DROP POLICY IF EXISTS "order_addons_staff_admin_all" ON public.order_addons;
DROP POLICY IF EXISTS "order_addons_customer_select" ON public.order_addons;
DROP POLICY IF EXISTS "order_addons_customer_insert" ON public.order_addons;

DROP POLICY IF EXISTS "dispatch_jobs_staff_admin_all" ON public.dispatch_jobs;
DROP POLICY IF EXISTS "dispatch_jobs_rider_all" ON public.dispatch_jobs;
DROP POLICY IF EXISTS "dispatch_jobs_customer_select" ON public.dispatch_jobs;

DROP POLICY IF EXISTS "rider_locations_all" ON public.rider_locations;

DROP POLICY IF EXISTS "gcash_settings_select" ON public.gcash_settings;
DROP POLICY IF EXISTS "gcash_settings_manage" ON public.gcash_settings;

DROP POLICY IF EXISTS "payments_staff_admin_all" ON public.payments;
DROP POLICY IF EXISTS "payments_customer_select" ON public.payments;
DROP POLICY IF EXISTS "payments_rider_select" ON public.payments;

DROP POLICY IF EXISTS "gcash_receipts_staff_admin_all" ON public.gcash_receipt_submissions;
DROP POLICY IF EXISTS "gcash_receipts_customer_all" ON public.gcash_receipt_submissions;

DROP POLICY IF EXISTS "rfid_cards_all" ON public.rfid_loyalty_cards;
DROP POLICY IF EXISTS "loyalty_history_all" ON public.loyalty_points_history;
DROP POLICY IF EXISTS "feedback_staff_admin" ON public.feedback;
DROP POLICY IF EXISTS "feedback_customer" ON public.feedback;

