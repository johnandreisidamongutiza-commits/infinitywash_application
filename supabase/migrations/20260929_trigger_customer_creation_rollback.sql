-- =====================================================
-- Trigger Customer Creation Rollback
-- =====================================================
-- Purpose: Revert the trigger to profile-only creation
-- Date: 2026-09-29
-- 
-- Run this ONLY if you need to undo the trigger changes
-- and go back to app-based customer creation
-- =====================================================

-- Step 1: Revert trigger function to original (profile only)
CREATE OR REPLACE FUNCTION handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only process customer role
  IF COALESCE(NEW.raw_user_meta_data->>'role', '') <> 'customer' THEN
    RETURN NEW;
  END IF;

  -- Only create profile (no customer creation)
  INSERT INTO public.profiles (
    id,
    supabase_user_id,
    first_name,
    last_name,
    email,
    phone,
    address,
    landmark,
    role,
    status,
    created_at,
    updated_at
  )
  VALUES (
    NEW.id,
    NEW.id,
    NEW.raw_user_meta_data->>'first_name',
    NEW.raw_user_meta_data->>'last_name',
    NEW.email,
    COALESCE(NEW.phone, NEW.raw_user_meta_data->>'phone'),
    NEW.raw_user_meta_data->>'address',
    NEW.raw_user_meta_data->>'landmark',
    'customer',
    'active',
    COALESCE(NEW.created_at, NOW()),
    NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    supabase_user_id = EXCLUDED.supabase_user_id,
    first_name = EXCLUDED.first_name,
    last_name = EXCLUDED.last_name,
    email = EXCLUDED.email,
    phone = EXCLUDED.phone,
    address = EXCLUDED.address,
    landmark = EXCLUDED.landmark,
    role = EXCLUDED.role,
    status = EXCLUDED.status,
    updated_at = NOW();

  RETURN NEW;
END;
$$;

-- Step 2: Revoke trigger permissions (optional - doesn't hurt to keep them)
-- REVOKE EXECUTE ON FUNCTION get_next_customer_code() FROM postgres;
-- REVOKE USAGE ON SEQUENCE customer_code_seq FROM postgres;

-- Verification
DO $$
BEGIN
  RAISE NOTICE '🔄 Trigger function reverted to profile-only creation';
  RAISE NOTICE 'App code (auth_service.dart) will handle customer creation';
  RAISE NOTICE 'Note: Permissions on sequence were NOT revoked (safe to keep)';
END $$;
