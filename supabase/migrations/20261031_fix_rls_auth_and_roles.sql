-- ====================================================================
-- Migration: 20261031_fix_rls_auth_and_roles.sql
-- Description: Establishes table grants, RLS policies, and 
--              SECURITY DEFINER helpers for core auth tables 
--              (profiles, employees, customers, legal_acceptances, fcm_tokens)
--              to fix 42501 permission denied errors and enable restricted
--              access across Customer, Staff, and Rider roles.
-- Date: 2026-10-31
-- ====================================================================

-- --------------------------------------------------------------------
-- STEP 0: Grant schema & table permissions to `authenticated` role
-- (Fixes "ERROR 42501: permission denied for table profiles / 403 Forbidden")
-- In PostgreSQL, RLS only works if the role first has table GRANTs.
-- RLS then restricts WHICH rows the authenticated user can see/modify.
-- --------------------------------------------------------------------
GRANT USAGE ON SCHEMA public TO anon, authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.profiles TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.employees TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.customers TO authenticated;

-- Grant sequence usage so ID / code generators work
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- --------------------------------------------------------------------
-- STEP 1: Create SECURITY DEFINER helper functions
-- (Prevents infinite RLS recursion loops when policies cross-reference)
-- --------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_auth_profile_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT id FROM public.profiles WHERE supabase_user_id = auth.uid() LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.get_auth_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT role FROM public.profiles WHERE supabase_user_id = auth.uid() LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.is_staff_or_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE supabase_user_id = auth.uid()
      AND role IN ('staff', 'admin', 'superadmin')
      AND status = 'active'
  );
$$;

CREATE OR REPLACE FUNCTION public.is_rider()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE supabase_user_id = auth.uid()
      AND role = 'rider'
      AND status = 'active'
  );
$$;

-- Grant execution to authenticated users
REVOKE ALL ON FUNCTION public.get_auth_profile_id() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_auth_profile_id() TO authenticated;

REVOKE ALL ON FUNCTION public.get_auth_role() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_auth_role() TO authenticated;

REVOKE ALL ON FUNCTION public.is_staff_or_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_staff_or_admin() TO authenticated;

REVOKE ALL ON FUNCTION public.is_rider() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_rider() TO authenticated;

-- --------------------------------------------------------------------
-- STEP 2: Row Level Security on `public.profiles`
-- --------------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Clean up any existing policies
DROP POLICY IF EXISTS "profiles_select_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_staff_admin" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_rider_view_customer" ON public.profiles;
DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_staff_admin" ON public.profiles;

-- 1. Read: Users read their own profile
CREATE POLICY "profiles_select_own"
  ON public.profiles FOR SELECT TO authenticated
  USING (supabase_user_id = auth.uid());

-- 2. Read: Staff & Admins can read all profiles
CREATE POLICY "profiles_select_staff_admin"
  ON public.profiles FOR SELECT TO authenticated
  USING (public.is_staff_or_admin());

-- 3. Read: Riders can view customer profiles for dispatch & delivery contact
CREATE POLICY "profiles_select_rider_view_customer"
  ON public.profiles FOR SELECT TO authenticated
  USING (public.is_rider() AND role = 'customer');

-- 4. Insert: Authenticated user can insert their own profile on signup / first login
CREATE POLICY "profiles_insert_own"
  ON public.profiles FOR INSERT TO authenticated
  WITH CHECK (supabase_user_id = auth.uid());

-- 5. Update: Users can update their own profile
CREATE POLICY "profiles_update_own"
  ON public.profiles FOR UPDATE TO authenticated
  USING (supabase_user_id = auth.uid())
  WITH CHECK (supabase_user_id = auth.uid());

-- 6. Update: Staff & Admins can update profiles
CREATE POLICY "profiles_update_staff_admin"
  ON public.profiles FOR UPDATE TO authenticated
  USING (public.is_staff_or_admin())
  WITH CHECK (public.is_staff_or_admin());

-- --------------------------------------------------------------------
-- STEP 3: Row Level Security on `public.employees`
-- --------------------------------------------------------------------
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "employees_select_own" ON public.employees;
DROP POLICY IF EXISTS "employees_select_staff_admin" ON public.employees;
DROP POLICY IF EXISTS "employees_select_active" ON public.employees;
DROP POLICY IF EXISTS "employees_update_own" ON public.employees;
DROP POLICY IF EXISTS "employees_update_staff_admin" ON public.employees;
DROP POLICY IF EXISTS "employees_insert_staff_admin" ON public.employees;

-- 1. Read: Staff and Riders read their own employee row
CREATE POLICY "employees_select_own"
  ON public.employees FOR SELECT TO authenticated
  USING (profile_id = public.get_auth_profile_id());

-- 2. Read: Staff and Admin can view all employees
CREATE POLICY "employees_select_staff_admin"
  ON public.employees FOR SELECT TO authenticated
  USING (public.is_staff_or_admin());

-- 3. Read: All authenticated users can view active employees (for delivery tracking rider details)
CREATE POLICY "employees_select_active"
  ON public.employees FOR SELECT TO authenticated
  USING (status = 'active');

-- 4. Update: Employees can update their own row (e.g. vehicle details, phone)
CREATE POLICY "employees_update_own"
  ON public.employees FOR UPDATE TO authenticated
  USING (profile_id = public.get_auth_profile_id())
  WITH CHECK (profile_id = public.get_auth_profile_id());

-- 5. Update: Staff & Admin can update employees
CREATE POLICY "employees_update_staff_admin"
  ON public.employees FOR UPDATE TO authenticated
  USING (public.is_staff_or_admin())
  WITH CHECK (public.is_staff_or_admin());

-- 6. Insert: Staff & Admin can insert new employees
CREATE POLICY "employees_insert_staff_admin"
  ON public.employees FOR INSERT TO authenticated
  WITH CHECK (public.is_staff_or_admin());

-- --------------------------------------------------------------------
-- STEP 4: Row Level Security on `public.customers`
-- --------------------------------------------------------------------
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "customers_select_own" ON public.customers;
DROP POLICY IF EXISTS "customers_select_staff_admin" ON public.customers;
DROP POLICY IF EXISTS "customers_select_rider" ON public.customers;
DROP POLICY IF EXISTS "customers_insert_own" ON public.customers;
DROP POLICY IF EXISTS "customers_insert_staff_admin" ON public.customers;
DROP POLICY IF EXISTS "customers_update_own" ON public.customers;
DROP POLICY IF EXISTS "customers_update_staff_admin" ON public.customers;

-- 1. Read: Customers read their own customer row
CREATE POLICY "customers_select_own"
  ON public.customers FOR SELECT TO authenticated
  USING (profile_id = public.get_auth_profile_id());

-- 2. Read: Staff & Admins can read all customer rows
CREATE POLICY "customers_select_staff_admin"
  ON public.customers FOR SELECT TO authenticated
  USING (public.is_staff_or_admin());

-- 3. Read: Riders can read customer rows for deliveries
CREATE POLICY "customers_select_rider"
  ON public.customers FOR SELECT TO authenticated
  USING (public.is_rider());

-- 4. Insert: Customers can create their own customer row
CREATE POLICY "customers_insert_own"
  ON public.customers FOR INSERT TO authenticated
  WITH CHECK (profile_id = public.get_auth_profile_id());

-- 5. Insert: Staff & Admins can insert customer records
CREATE POLICY "customers_insert_staff_admin"
  ON public.customers FOR INSERT TO authenticated
  WITH CHECK (public.is_staff_or_admin());

-- 6. Update: Customers can update their own customer record (e.g. address sync)
CREATE POLICY "customers_update_own"
  ON public.customers FOR UPDATE TO authenticated
  USING (profile_id = public.get_auth_profile_id())
  WITH CHECK (profile_id = public.get_auth_profile_id());

-- 7. Update: Staff & Admins can update customer records
CREATE POLICY "customers_update_staff_admin"
  ON public.customers FOR UPDATE TO authenticated
  USING (public.is_staff_or_admin())
  WITH CHECK (public.is_staff_or_admin());

-- --------------------------------------------------------------------
-- STEP 5: Row Level Security on `public.legal_acceptances` (if table exists)
-- --------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_name = 'legal_acceptances'
  ) THEN
    EXECUTE 'GRANT SELECT, INSERT ON TABLE public.legal_acceptances TO authenticated';
    EXECUTE 'ALTER TABLE public.legal_acceptances ENABLE ROW LEVEL SECURITY';

    EXECUTE 'DROP POLICY IF EXISTS "Users can insert own legal acceptances" ON public.legal_acceptances';
    EXECUTE 'DROP POLICY IF EXISTS "Users can select own legal acceptances" ON public.legal_acceptances';
    EXECUTE 'DROP POLICY IF EXISTS "Staff can read legal acceptances" ON public.legal_acceptances';

    EXECUTE 'CREATE POLICY "Users can insert own legal acceptances"
      ON public.legal_acceptances FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid())';

    EXECUTE 'CREATE POLICY "Users can select own legal acceptances"
      ON public.legal_acceptances FOR SELECT TO authenticated
      USING (user_id = auth.uid())';

    EXECUTE 'CREATE POLICY "Staff can read legal acceptances"
      ON public.legal_acceptances FOR SELECT TO authenticated
      USING (public.is_staff_or_admin())';
  END IF;
END $$;

-- --------------------------------------------------------------------
-- STEP 6: Row Level Security on `public.fcm_tokens` (if table exists)
-- --------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_name = 'fcm_tokens'
  ) THEN
    EXECUTE 'GRANT ALL ON TABLE public.fcm_tokens TO authenticated';
    EXECUTE 'ALTER TABLE public.fcm_tokens ENABLE ROW LEVEL SECURITY';

    EXECUTE 'DROP POLICY IF EXISTS "Users can insert own fcm tokens" ON public.fcm_tokens';
    EXECUTE 'DROP POLICY IF EXISTS "Users can select own fcm tokens" ON public.fcm_tokens';
    EXECUTE 'DROP POLICY IF EXISTS "Users can update own fcm tokens" ON public.fcm_tokens';
    EXECUTE 'DROP POLICY IF EXISTS "Users can delete own fcm tokens" ON public.fcm_tokens';

    EXECUTE 'CREATE POLICY "Users can insert own fcm tokens"
      ON public.fcm_tokens FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid())';

    EXECUTE 'CREATE POLICY "Users can select own fcm tokens"
      ON public.fcm_tokens FOR SELECT TO authenticated
      USING (user_id = auth.uid())';

    EXECUTE 'CREATE POLICY "Users can update own fcm tokens"
      ON public.fcm_tokens FOR UPDATE TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid())';

    EXECUTE 'CREATE POLICY "Users can delete own fcm tokens"
      ON public.fcm_tokens FOR DELETE TO authenticated
      USING (user_id = auth.uid())';
  END IF;
END $$;
