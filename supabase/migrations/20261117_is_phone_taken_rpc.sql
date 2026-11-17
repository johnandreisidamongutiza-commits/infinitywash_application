-- Migration: Add is_phone_taken RPC function with SECURITY DEFINER
-- Allows registration and profile editing to check phone uniqueness across
-- profiles, customers, and employees safely without exposing personal data or violating RLS.

CREATE OR REPLACE FUNCTION public.is_phone_taken(
  p_phone TEXT,
  p_exclude_user_id UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_norm TEXT;
  v_found BOOLEAN := FALSE;
BEGIN
  IF p_phone IS NULL OR trim(p_phone) = '' THEN
    RETURN FALSE;
  END IF;

  v_norm := normalize_ph_phone(p_phone);
  IF v_norm = '' THEN
    RETURN FALSE;
  END IF;

  -- 1. Check profiles (checks both supabase_user_id and profile id)
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE normalize_ph_phone(phone) = v_norm
      AND (
        p_exclude_user_id IS NULL
        OR (supabase_user_id <> p_exclude_user_id AND id <> p_exclude_user_id)
      )
  ) INTO v_found;

  IF v_found THEN
    RETURN TRUE;
  END IF;

  -- 2. Check customers
  SELECT EXISTS (
    SELECT 1 FROM public.customers c
    WHERE normalize_ph_phone(c.phone) = v_norm
      AND (
        p_exclude_user_id IS NULL
        OR (
          (c.profile_id IS NULL OR c.profile_id <> p_exclude_user_id)
          AND NOT EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = c.profile_id AND p.supabase_user_id = p_exclude_user_id
          )
        )
      )
  ) INTO v_found;

  IF v_found THEN
    RETURN TRUE;
  END IF;

  -- 3. Check employees
  SELECT EXISTS (
    SELECT 1 FROM public.employees e
    WHERE normalize_ph_phone(e.phone) = v_norm
      AND (
        p_exclude_user_id IS NULL
        OR (
          (e.profile_id IS NULL OR e.profile_id <> p_exclude_user_id)
          AND NOT EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = e.profile_id AND p.supabase_user_id = p_exclude_user_id
          )
        )
      )
  ) INTO v_found;

  RETURN v_found;
END;
$$;

-- Grant permissions to anon, authenticated, and service_role
REVOKE ALL ON FUNCTION public.is_phone_taken(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_phone_taken(TEXT, UUID) TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.is_phone_taken(TEXT, UUID) IS
  'Checks if a phone number is already registered across profiles, customers, or employees, safely bypassing RLS without revealing personal data.';

