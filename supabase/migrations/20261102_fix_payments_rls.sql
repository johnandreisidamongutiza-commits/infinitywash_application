-- ====================================================================
-- Migration: 20261102_fix_payments_rls.sql
-- Description: Fixes 42501 "new row violates row-level security policy
--              for table 'payments'" by allowing Riders and Customers
--              to INSERT/UPDATE payment records (e.g. collecting cash/GCash).
-- Date: 2026-11-02
-- ====================================================================

ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

-- Clean up existing payment policies
DROP POLICY IF EXISTS "payments_staff_admin_all" ON public.payments;
DROP POLICY IF EXISTS "payments_rider_select" ON public.payments;
DROP POLICY IF EXISTS "payments_rider_all" ON public.payments;
DROP POLICY IF EXISTS "payments_customer_select" ON public.payments;
DROP POLICY IF EXISTS "payments_customer_all" ON public.payments;

-- 1. Staff & Admin: Full access to all payments
CREATE POLICY "payments_staff_admin_all"
  ON public.payments FOR ALL TO authenticated
  USING (public.is_staff_or_admin())
  WITH CHECK (public.is_staff_or_admin());

-- 2. Riders: Full access (to collect cash/GCash on delivery and view payment history)
CREATE POLICY "payments_rider_all"
  ON public.payments FOR ALL TO authenticated
  USING (public.is_rider())
  WITH CHECK (public.is_rider());

-- 3. Customers: Can view and create payments for their own orders
CREATE POLICY "payments_customer_all"
  ON public.payments FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      JOIN public.customers c ON c.id = o.customer_id
      WHERE o.id = payments.order_id
        AND c.profile_id = public.get_auth_profile_id()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.orders o
      JOIN public.customers c ON c.id = o.customer_id
      WHERE o.id = payments.order_id
        AND c.profile_id = public.get_auth_profile_id()
    )
  );

