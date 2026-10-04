-- =====================================================
-- Legal Acceptances Migration - ROLLBACK
-- =====================================================
-- Purpose: Undo 20261005_legal_acceptances.sql.
--
--   1. Drop the legal_acceptances policies and table
--      (including its consent evidence rows).
--   2. Restore handle_new_auth_user() to the exact body
--      from 20261002_customer_pin_location.sql, which had
--      NO consent enforcement.
--
-- ⚠️ After rolling back, customer registrations created by
--    the app will succeed again but their consent will NOT
--    be recorded anywhere. Only roll back if you are also
--    reverting the app release that added the consent flow.
--
-- Idempotent: safe to run more than once.
-- Date: 2026-10-05
-- =====================================================

-- -----------------------------------------------------
-- Step 1: Drop RLS policies, then the table.
-- Dropping the table alone would be enough (policies die
-- with it) but explicit drops keep repeated runs clean.
-- -----------------------------------------------------
DROP POLICY IF EXISTS "Users can insert own legal acceptances" ON public.legal_acceptances;
DROP POLICY IF EXISTS "Users can select own legal acceptances" ON public.legal_acceptances;
DROP POLICY IF EXISTS "Staff can read legal acceptances"       ON public.legal_acceptances;

DROP TABLE IF EXISTS public.legal_acceptances CASCADE;

-- -----------------------------------------------------
-- Step 2: Restore the registration trigger to the exact
-- body from 20261002_customer_pin_location.sql (pin
-- support, no consent enforcement).
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_customer_code TEXT;
  new_profile_id UUID;
  pin_lat  double precision;
  pin_lng  double precision;
BEGIN
  -- Only process customer role registrations
  IF COALESCE(NEW.raw_user_meta_data->>'role', '') <> 'customer' THEN
    RETURN NEW;
  END IF;

  -- Parse optional pin coordinates from metadata.
  -- NULLIF handles the empty-string case (customer skipped the pin).
  pin_lat := NULLIF(NEW.raw_user_meta_data->>'latitude', '')::double precision;
  pin_lng := NULLIF(NEW.raw_user_meta_data->>'longitude', '')::double precision;

  RAISE NOTICE 'Processing customer registration for user % (pin: %, %)', NEW.id, pin_lat, pin_lng;

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
    pin_latitude,
    pin_longitude,
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
    pin_lat,
    pin_lng,
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
    pin_latitude = EXCLUDED.pin_latitude,
    pin_longitude = EXCLUDED.pin_longitude,
    role = EXCLUDED.role,
    status = EXCLUDED.status,
    updated_at = NOW()
  RETURNING id INTO new_profile_id;

  RAISE NOTICE 'Profile created/updated: %', new_profile_id;

  -- Step 2: Create customer record
  BEGIN
    -- Generate customer code using sequence
    new_customer_code := get_next_customer_code();

    IF new_customer_code IS NULL THEN
      RAISE WARNING 'Sequence returned NULL, using fallback customer code';
      new_customer_code := 'CUST-' || LPAD(FLOOR(RANDOM() * 99999)::TEXT, 5, '0');
    END IF;

    RAISE NOTICE 'Generated customer code: %', new_customer_code;

    -- Insert customer record
    INSERT INTO public.customers (
      customer_code,
      profile_id,
      first_name,
      last_name,
      phone,
      email,
      address,
      landmark,
      pin_latitude,
      pin_longitude,
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
      pin_lat,
      pin_lng,
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
      -- Log error but don't fail the registration
      RAISE WARNING 'Customer creation failed for profile %: % (SQLSTATE: %)',
                    new_profile_id, SQLERRM, SQLSTATE;
      -- Profile is still created, app code can create customer as fallback
  END;

  RETURN NEW;
END;
$$;

-- -----------------------------------------------------
-- Step 3: Restore the pin-location migration's COMMENT
-- -----------------------------------------------------
COMMENT ON FUNCTION handle_new_auth_user() IS
  'Trigger function that creates profile and customer records when a user registers. '
  'Uses database sequence for customer codes to prevent race conditions. '
  'Also persists optional pin_latitude/pin_longitude from registration metadata. '
  'Includes error handling to ensure registration succeeds even if customer creation fails.';

-- -----------------------------------------------------
-- Step 4: Verify trigger still exists and is enabled
-- -----------------------------------------------------
DO $$
DECLARE
  trigger_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO trigger_count
  FROM pg_trigger
  WHERE tgname = 'on_auth_user_created'
    AND tgrelid = 'auth.users'::regclass;

  IF trigger_count = 0 THEN
    CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION handle_new_auth_user();

    RAISE NOTICE 'Step 4 ✅ Recreated trigger on_auth_user_created';
  ELSE
    RAISE NOTICE 'Step 4 ✅ Trigger on_auth_user_created already exists';
  END IF;
END $$;

-- =====================================================
-- Rollback Complete!
-- =====================================================
DO $$
BEGIN
  RAISE NOTICE '🎉 Rollback completed successfully!';
  RAISE NOTICE 'legal_acceptances dropped; consent enforcement removed';
  RAISE NOTICE '⚠️ Registrations will no longer record consent';
END $$;
