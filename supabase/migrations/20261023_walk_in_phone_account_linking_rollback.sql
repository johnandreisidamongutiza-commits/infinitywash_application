-- =========================================================================
-- Rollback Migration: Automatic Walk-in Customer Account Linking via Phone Number
-- Date: 2026-10-23
-- Description:
--   1. Drops sync_customer_walkin_orders(UUID).
--   2. Restores handle_new_auth_user() to the exact version from 20261005_legal_acceptances.sql.
--   3. Drops normalize_ph_phone(TEXT).
-- =========================================================================

-- Step 1: Drop the sync helper
DROP FUNCTION IF EXISTS sync_customer_walkin_orders(UUID);

-- Step 2: Restore handle_new_auth_user to pre-linking logic
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
BEGIN
  IF COALESCE(NEW.raw_user_meta_data->>'role', '') <> 'customer' THEN
    RETURN NEW;
  END IF;

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

  pin_lat := NULLIF(NEW.raw_user_meta_data->>'latitude', '')::double precision;
  pin_lng := NULLIF(NEW.raw_user_meta_data->>'longitude', '')::double precision;

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

  BEGIN
    new_customer_code := get_next_customer_code();

    IF new_customer_code IS NULL THEN
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

  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'Customer creation failed for profile %: % (SQLSTATE: %)',
                    new_profile_id, SQLERRM, SQLSTATE;
  END;

  RETURN NEW;
END;
$$;

-- Step 3: Drop the phone normalizer
DROP FUNCTION IF EXISTS normalize_ph_phone(TEXT);
