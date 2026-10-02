-- =====================================================
-- Customer Pin Location Rollback Migration
-- =====================================================
-- Purpose: Revert the pin location columns and restore the
--          previous trigger behavior (no pin handling).
-- Run this ONLY if you need to undo 20261002_customer_pin_location.sql
-- Date: 2026-10-02
-- =====================================================

-- Step 1: Restore the previous trigger function (no pin handling)
CREATE OR REPLACE FUNCTION handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_customer_code TEXT;
  new_profile_id UUID;
BEGIN
  -- Only process customer role registrations
  IF COALESCE(NEW.raw_user_meta_data->>'role', '') <> 'customer' THEN
    RETURN NEW;
  END IF;

  -- Step 1: Create or update profile
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
    updated_at = NOW()
  RETURNING id INTO new_profile_id;

  RAISE NOTICE 'Profile created/updated: %', new_profile_id;

  -- Step 2: Create customer record
  BEGIN
    new_customer_code := get_next_customer_code();

    IF new_customer_code IS NULL THEN
      RAISE WARNING 'Sequence returned NULL, using fallback customer code';
      new_customer_code := 'CUST-' || LPAD(FLOOR(RANDOM() * 99999)::TEXT, 5, '0');
    END IF;

    INSERT INTO public.customers (
      customer_code,
      profile_id,
      first_name,
      last_name,
      phone,
      email,
      address,
      landmark,
      customer_type,
      status,
      joined_at,
      created_at,
      updated_at
    )
    VALUES (
      new_customer_code,
      new_profile_id,
      NEW.raw_user_meta_data->>'first_name',
      NEW.raw_user_meta_data->>'last_name',
      COALESCE(NEW.phone, NEW.raw_user_meta_data->>'phone'),
      NEW.email,
      NEW.raw_user_meta_data->>'address',
      NEW.raw_user_meta_data->>'landmark',
      'mobile_app',
      'active',
      NOW(),
      NOW(),
      NOW()
    )
    ON CONFLICT (profile_id) DO NOTHING;

    RAISE NOTICE 'Customer created: % for profile %', new_customer_code, new_profile_id;

  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'Customer creation failed for profile %: % (SQLSTATE: %)',
                    new_profile_id, SQLERRM, SQLSTATE;
  END;

  RETURN NEW;
END;
$$;

-- Step 2: Drop the pin columns
ALTER TABLE public.customers
  DROP COLUMN IF EXISTS pin_latitude,
  DROP COLUMN IF EXISTS pin_longitude;

ALTER TABLE public.profiles
  DROP COLUMN IF EXISTS pin_latitude,
  DROP COLUMN IF EXISTS pin_longitude;

-- Step 3: Restore previous function comment
COMMENT ON FUNCTION handle_new_auth_user() IS
  'Trigger function that creates profile and customer records when a user registers. '
  'Uses database sequence for customer codes to prevent race conditions. '
  'Includes error handling to ensure registration succeeds even if customer creation fails.';

DO $$
BEGIN
  RAISE NOTICE '🎉 Rollback completed successfully!';
  RAISE NOTICE 'Pin columns dropped and trigger restored to pre-pin behavior';
END $$;
