-- =====================================================
-- Disable Old Customer Creation Trigger
-- =====================================================
-- Purpose: Disable the old trigger_create_customer_for_profile
--          to prevent conflicts with handle_new_auth_user
-- Date: 2026-09-29
-- 
-- The handle_new_auth_user trigger on auth.users already
-- creates customers during registration, so we don't need
-- the profiles table trigger anymore.
-- =====================================================

-- Step 1: Disable the old trigger on profiles table
ALTER TABLE profiles DISABLE TRIGGER trigger_create_customer_for_profile;

RAISE NOTICE '✅ Disabled trigger_create_customer_for_profile on profiles table';

-- Step 2: Verify the trigger is disabled
DO $$
DECLARE
  trigger_status TEXT;
BEGIN
  SELECT tgenabled INTO trigger_status
  FROM pg_trigger
  WHERE tgname = 'trigger_create_customer_for_profile'
    AND tgrelid = 'profiles'::regclass;
  
  IF trigger_status = 'D' THEN
    RAISE NOTICE '✅ Trigger is now DISABLED';
  ELSE
    RAISE NOTICE '⚠️ Trigger status: %', trigger_status;
  END IF;
END $$;

-- Step 3: Show active triggers
SELECT 
  'Active triggers on auth.users:' AS info,
  trigger_name,
  event_manipulation,
  tgenabled AS status
FROM pg_trigger t
JOIN information_schema.triggers i 
  ON t.tgname = i.trigger_name
WHERE i.event_object_schema = 'auth'
  AND i.event_object_table = 'users'
  AND t.tgenabled != 'D';

-- =====================================================
-- Migration Complete!
-- =====================================================
-- Now only handle_new_auth_user will create customers
-- during registration, eliminating the conflict.
-- 
-- Try registering a new customer now!
-- =====================================================
