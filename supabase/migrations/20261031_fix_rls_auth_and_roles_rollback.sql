-- ====================================================================
-- Rollback: 20261031_fix_rls_auth_and_roles_rollback.sql
-- Description: Reverts the RLS policies and functions added in
--              20261031_fix_rls_auth_and_roles.sql.
-- ====================================================================

-- Drop policies on profiles
DROP POLICY IF EXISTS "profiles_select_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_staff_admin" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_rider_view_customer" ON public.profiles;
DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_staff_admin" ON public.profiles;

-- Drop policies on employees
DROP POLICY IF EXISTS "employees_select_own" ON public.employees;
DROP POLICY IF EXISTS "employees_select_staff_admin" ON public.employees;
DROP POLICY IF EXISTS "employees_select_active" ON public.employees;
DROP POLICY IF EXISTS "employees_update_own" ON public.employees;
DROP POLICY IF EXISTS "employees_update_staff_admin" ON public.employees;
DROP POLICY IF EXISTS "employees_insert_staff_admin" ON public.employees;

-- Drop policies on customers
DROP POLICY IF EXISTS "customers_select_own" ON public.customers;
DROP POLICY IF EXISTS "customers_select_staff_admin" ON public.customers;
DROP POLICY IF EXISTS "customers_select_rider" ON public.customers;
DROP POLICY IF EXISTS "customers_insert_own" ON public.customers;
DROP POLICY IF EXISTS "customers_insert_staff_admin" ON public.customers;
DROP POLICY IF EXISTS "customers_update_own" ON public.customers;
DROP POLICY IF EXISTS "customers_update_staff_admin" ON public.customers;

-- Drop helper functions
DROP FUNCTION IF EXISTS public.is_rider();
DROP FUNCTION IF EXISTS public.is_staff_or_admin();
DROP FUNCTION IF EXISTS public.get_auth_role();
DROP FUNCTION IF EXISTS public.get_auth_profile_id();

