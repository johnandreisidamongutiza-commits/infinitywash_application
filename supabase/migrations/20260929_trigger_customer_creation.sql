-- =====================================================
-- Trigger Customer Creation Migration
-- =====================================================
-- Purpose: Update handle_new_auth_user trigger to create
--          both profile AND customer during registration
-- Date: 2026-09-29
-- 
-- This fixes the registration error by allowing the trigger
-- to automatically create customer records using the sequence.
-- =====================================================

-- Step 1: Grant permissions for trigger to use sequence
-- The trigger runs as SECURITY DEFINER with postgres role
GRANT EXECUTE ON FUNCTION get_next_customer_code() TO postgres;
GRANT USAGE ON SEQUENCE customer_code_seq TO postgres;

-- Also ensure anon can use it during registration context
GRANT EXECUTE ON FUNCTION get_next_customer_code() TO anon;

-- Step 2: Update trigger function to create customers
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

  RAISE NOTICE 'Processing customer registration for user %', NEW.id;

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
      -- Log error but don't fail the registration
      RAISE WARNING 'Customer creation failed for profile %: % (SQLSTATE: %)', 
                    new_profile_id, SQLERRM, SQLSTATE;
      -- Profile is still created, app code can create customer as fallback
  END;

  RETURN NEW;
END;
$$;

-- Step 3: Verify trigger still exists and is enabled
DO $$
DECLARE
  trigger_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO trigger_count
  FROM pg_trigger
  WHERE tgname = 'on_auth_user_created'
    AND tgrelid = 'auth.users'::regclass;
  
  IF trigger_count = 0 THEN
    -- Recreate trigger if it doesn't exist
    CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION handle_new_auth_user();
    
    RAISE NOTICE 'Step 3 ✅ Recreated trigger on_auth_user_created';
  ELSE
    RAISE NOTICE 'Step 3 ✅ Trigger on_auth_user_created already exists';
  END IF;
END $$;

-- Step 4: Add helpful comments
COMMENT ON FUNCTION handle_new_auth_user() IS 
  'Trigger function that creates profile and customer records when a user registers. '
  'Uses database sequence for customer codes to prevent race conditions. '
  'Includes error handling to ensure registration succeeds even if customer creation fails.';

-- =====================================================
-- Migration Complete!
-- =====================================================
-- Next steps:
-- 1. Run verify_trigger_customer_creation.sql to test
-- 2. Try registering a test user in your app
-- 3. Check database to confirm customer was created
-- =====================================================

-- Final verification
DO $$
BEGIN
  RAISE NOTICE '🎉 Migration completed successfully!';
  RAISE NOTICE 'Trigger now creates profile + customer during registration';
  RAISE NOTICE 'Run verify_trigger_customer_creation.sql to test';
END $$;
