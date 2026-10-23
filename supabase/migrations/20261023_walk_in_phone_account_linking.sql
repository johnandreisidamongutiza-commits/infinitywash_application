-- =========================================================================
-- Migration: Automatic Walk-in Customer Account Linking via Phone Number
-- Date: 2026-10-23
-- Description:
--   1. Adds normalize_ph_phone(TEXT) to standardize Philippine phone numbers
--      (e.g., '09171234567', '+639171234567', '0917-123-4567' -> '+639171234567').
--   2. Updates handle_new_auth_user() trigger on auth.users:
--      - When a customer registers on their phone, checks if an unclaimed
--        walk-in customer record exists with the matching normalized phone.
--      - If found: links the existing walk-in customer record to the new
--        profile (profile_id = new_profile_id, customer_type = 'mobile_app'),
--        preserving the customer code and all existing orders.
--      - Consolidates any duplicate walk-in customer orders under this profile.
--      - If not found: creates a new customer row with a new code as usual.
--   3. Adds sync_customer_walkin_orders(p_customer_id UUID) to pull any
--      unclaimed walk-in orders matching the customer's phone at any time.
-- =========================================================================

-- Step 1: Philippine Phone Normalization Function
CREATE OR REPLACE FUNCTION normalize_ph_phone(p_phone TEXT)
RETURNS TEXT AS $$
DECLARE
  v_digits TEXT;
BEGIN
  IF p_phone IS NULL OR TRIM(p_phone) = '' THEN
    RETURN NULL;
  END IF;

  -- Strip all non-digit characters
  v_digits := REGEXP_REPLACE(p_phone, '[^0-9]', '', 'g');

  -- Convert 09XXXXXXXXX (11 digits) -> +639XXXXXXXXX
  IF LENGTH(v_digits) = 11 AND v_digits LIKE '09%' THEN
    RETURN '+63' || SUBSTRING(v_digits FROM 2);
  END IF;

  -- Convert 639XXXXXXXXX (12 digits) -> +639XXXXXXXXX
  IF LENGTH(v_digits) = 12 AND v_digits LIKE '639%' THEN
    RETURN '+' || v_digits;
  END IF;

  -- Convert 9XXXXXXXXX (10 digits) -> +639XXXXXXXXX
  IF LENGTH(v_digits) = 10 AND v_digits LIKE '9%' THEN
    RETURN '+63' || v_digits;
  END IF;

  RETURN '+' || v_digits;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Step 2: Update handle_new_auth_user trigger function
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
  v_consents jsonb;
  v_required text[] := ARRAY['terms_of_service', 'privacy_policy'];
  v_accepted text[] := ARRAY[]::text[];
  v_key   text;
  v_ver   text;
  v_hash  text;
  v_app_version text;
  v_rec   record;
  v_raw_phone TEXT;
  v_norm_phone TEXT;
  v_walkin_customer_id UUID;
BEGIN
  -- Only process customer role registrations
  IF COALESCE(NEW.raw_user_meta_data->>'role', '') <> 'customer' THEN
    RETURN NEW;
  END IF;

  -- ---------------------------------------------------
  -- Step 0: Consent enforcement + acceptance records
  -- ---------------------------------------------------
  IF COALESCE(NEW.raw_user_meta_data->>'legal_accepted_by_admin', '') <> 'true' THEN
    v_consents := NEW.raw_user_meta_data->'legal_acceptances';

    IF COALESCE(jsonb_typeof(v_consents), '') <> 'array' OR jsonb_array_length(v_consents) = 0 THEN
      RAISE EXCEPTION
        'Registration requires acceptance of the Terms of Service and Privacy Policy'
        USING HINT = 'Send legal_acceptances: [{key, version, hash}] in user metadata';
    END IF;

    v_app_version := NULLIF(NEW.raw_user_meta_data->>'app_version', '');

    FOR v_rec IN
      SELECT elem->>'key'     AS key,
             elem->>'version' AS version,
             elem->>'hash'    AS hash
      FROM jsonb_array_elements(v_consents) AS elem
    LOOP
      v_key  := NULLIF(v_rec.key, '');
      v_ver  := NULLIF(v_rec.version, '');
      v_hash := NULLIF(v_rec.hash, '');

      IF v_key IS NULL OR v_ver IS NULL OR v_hash IS NULL THEN
        RAISE EXCEPTION
          'Malformed legal_acceptances entry for user % (key/version/hash must all be present)',
          NEW.id;
      END IF;

      IF NOT (v_key = ANY (v_required)) THEN
        RAISE EXCEPTION
          'Unknown legal document key "%" (required: %)', v_key, array_to_string(v_required, ', ');
      END IF;

      INSERT INTO public.legal_acceptances (
        user_id,
        document_key,
        document_version,
        document_hash,
        app_version,
        source
      ) VALUES (
        NEW.id,
        v_key,
        v_ver,
        v_hash,
        v_app_version,
        'registration'
      )
      ON CONFLICT (user_id, document_key, document_version) DO NOTHING;

      v_accepted := array_append(v_accepted, v_key);
    END LOOP;

    IF NOT (v_required <@ v_accepted) THEN
      RAISE EXCEPTION
        'Registration requires acceptance of the Terms of Service and Privacy Policy (missing: %)',
        array_to_string(v_required - v_accepted, ', ');
    END IF;
  END IF;

  -- Parse optional pin coordinates
  pin_lat := NULLIF(NEW.raw_user_meta_data->>'latitude', '')::double precision;
  pin_lng := NULLIF(NEW.raw_user_meta_data->>'longitude', '')::double precision;

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

  -- Step 2: Create or link customer record
  BEGIN
    v_raw_phone := COALESCE(NEW.phone, NEW.raw_user_meta_data->>'phone');
    v_norm_phone := normalize_ph_phone(v_raw_phone);

    -- Search for existing unclaimed walk-in customer record with this phone
    IF v_norm_phone IS NOT NULL THEN
      SELECT id INTO v_walkin_customer_id
      FROM public.customers
      WHERE normalize_ph_phone(phone) = v_norm_phone
        AND customer_type = 'walk_in'
        AND profile_id IS NULL
      ORDER BY created_at ASC
      LIMIT 1;
    END IF;

    IF v_walkin_customer_id IS NOT NULL THEN
      -- Link existing walk-in customer to new mobile profile
      UPDATE public.customers
      SET profile_id = new_profile_id,
          customer_type = 'mobile_app',
          email = COALESCE(email, NEW.email),
          address = COALESCE(address, NEW.raw_user_meta_data->>'address'),
          landmark = COALESCE(landmark, NEW.raw_user_meta_data->>'landmark'),
          pin_latitude = COALESCE(pin_latitude, pin_lat),
          pin_longitude = COALESCE(pin_longitude, pin_lng),
          updated_at = NOW()
      WHERE id = v_walkin_customer_id;

      -- Consolidate any duplicate walk-in customer orders with this phone
      UPDATE public.orders
      SET customer_id = v_walkin_customer_id,
          updated_at = NOW()
      WHERE customer_id IN (
        SELECT id FROM public.customers
        WHERE normalize_ph_phone(phone) = v_norm_phone
          AND id <> v_walkin_customer_id
          AND profile_id IS NULL
          AND customer_type = 'walk_in'
      );

      RAISE NOTICE 'Linked existing walk-in customer % to mobile profile %', v_walkin_customer_id, new_profile_id;
    ELSE
      -- Generate customer code using sequence
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
        v_raw_phone,
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
    END IF;

  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'Customer creation/linking failed for profile %: % (SQLSTATE: %)',
                    new_profile_id, SQLERRM, SQLSTATE;
  END;

  RETURN NEW;
END;
$$;

-- Step 3: Reusable function to sync any past walk-in orders by customer phone at any time
CREATE OR REPLACE FUNCTION sync_customer_walkin_orders(p_customer_id UUID)
RETURNS INTEGER AS $$
DECLARE
  v_phone TEXT;
  v_norm_phone TEXT;
  v_count INTEGER := 0;
BEGIN
  SELECT phone INTO v_phone FROM public.customers WHERE id = p_customer_id;
  v_norm_phone := normalize_ph_phone(v_phone);

  IF v_norm_phone IS NULL THEN
    RETURN 0;
  END IF;

  WITH moved_orders AS (
    UPDATE public.orders
    SET customer_id = p_customer_id,
        updated_at = NOW()
    WHERE customer_id IN (
      SELECT id FROM public.customers
      WHERE normalize_ph_phone(phone) = v_norm_phone
        AND id <> p_customer_id
        AND profile_id IS NULL
        AND customer_type = 'walk_in'
    )
    RETURNING id
  )
  SELECT COUNT(*) INTO v_count FROM moved_orders;

  RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 4: Ensure trigger is active
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
  END IF;
END $$;
