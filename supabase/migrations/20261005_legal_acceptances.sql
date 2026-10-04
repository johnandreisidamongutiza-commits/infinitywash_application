-- =====================================================
-- Legal Acceptances (Terms of Service / Privacy Policy)
-- =====================================================
-- Purpose: Record, with tamper-evident detail, that a user
--          accepted each version of our legal documents.
--
--   * The Flutter app bundles the document text as Markdown
--     assets (assets/legal/). The manifest in
--     lib/config/legal_documents.dart declares the version
--     of each document and the app computes a sha256 of the
--     exact bytes it displayed. Both are sent during
--     registration inside auth metadata:
--
--         'legal_acceptances': [
--           { "key": "terms_of_service", "version": "1.0", "hash": "<sha256>" },
--           { "key": "privacy_policy",   "version": "1.0", "hash": "<sha256>" }
--         ]
--
--   * handle_new_auth_user() (AFTER INSERT on auth.users)
--     writes one legal_acceptances row per accepted document
--     and REFUSES the registration when the required
--     documents are missing. Consent is therefore bound to
--     the account-creation event on the server, not left to
--     the client UI.
--
-- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
-- BREAKING CHANGE for the ADMIN WEBSITE:
-- Any INSERT into auth.users with
--   raw_user_meta_data->>'role' = 'customer'
-- MUST now include the 'legal_acceptances' array above
-- (or set 'legal_accepted_by_admin' = true, for staff who
-- completed consent on paper). Otherwise the insert fails
-- with a clear error. Non-customer roles (staff, rider,
-- admin) are unaffected - the trigger returns early for
-- them, exactly as before.
-- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
--
-- Design notes:
--   * UNIQUE (user_id, document_key, document_version)
--     makes re-accepting the same version idempotent, while
--     a NEW version creates a new row - so history across
--     versions is preserved and each row can be tied back
--     to the exact text via document_hash.
--   * ON DELETE CASCADE mirrors
--     profiles_supabase_user_id_fkey: consent evidence is
--     meaningful only while the account exists, and deleting
--     the account deletes its data with it.
--   * The trigger's acceptance INSERT is deliberately NOT
--     wrapped in an exception-swallowing block: if consent
--     cannot be recorded, the registration must fail.
--   * ip_address / user_agent are NOT captured here because
--     a Flutter client cannot see them. Add an Edge Function
--     before extending the table.
--
-- Required document keys are duplicated between the app
-- (legal_documents.dart, required: true) and the trigger
-- below. Both must be updated together - the server side is
-- what actually enforces the rule.
--
-- Idempotent: safe to run more than once.
-- Date: 2026-10-05
-- =====================================================

-- -----------------------------------------------------
-- Step 1: Acceptance records table
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS public.legal_acceptances (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL,               -- auth.users.id
  document_key     varchar(50) NOT NULL,        -- 'terms_of_service' | 'privacy_policy'
  document_version varchar(20) NOT NULL,        -- matches lib/config/legal_documents.dart
  document_hash    text NOT NULL,               -- sha256 of the exact asset text shown
  app_version      varchar(30),                 -- app build the user accepted on
  source           varchar(20) NOT NULL DEFAULT 'registration'
                   CHECK (source IN ('registration', 'in_app_prompt')),
  accepted_at      timestamptz NOT NULL DEFAULT NOW(),

  -- One row per (user, document, version). Same version
  -- re-accepted = no-op; new version = new row, so history
  -- is preserved.
  CONSTRAINT legal_acceptances_user_doc_version_unique
    UNIQUE (user_id, document_key, document_version)
);

-- -----------------------------------------------------
-- Step 2: Lookup index
-- -----------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_legal_acceptances_user_id
  ON public.legal_acceptances (user_id);

-- -----------------------------------------------------
-- Step 3: Row Level Security
-- Users read/write only their own rows. Staff and admins
-- get read-only access so a manager can prove a customer
-- agreed. The admin website uses the service role key,
-- which bypasses RLS by design.
-- -----------------------------------------------------
ALTER TABLE public.legal_acceptances ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can insert own legal acceptances" ON public.legal_acceptances;
DROP POLICY IF EXISTS "Users can select own legal acceptances" ON public.legal_acceptances;
DROP POLICY IF EXISTS "Staff can read legal acceptances"       ON public.legal_acceptances;

CREATE POLICY "Users can insert own legal acceptances"
  ON public.legal_acceptances FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can select own legal acceptances"
  ON public.legal_acceptances FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Staff can read legal acceptances"
  ON public.legal_acceptances FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('staff', 'admin', 'superadmin')
    )
  );

-- -----------------------------------------------------
-- Step 4: Registration trigger with consent enforcement
-- Extends the 20261002_customer_pin_location version,
-- adding Step 0 (consent guard + acceptance rows) and
-- leaving the profile/customer logic untouched.
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
  v_consents jsonb;
  v_required text[] := ARRAY['terms_of_service', 'privacy_policy'];
  v_accepted text[] := ARRAY[]::text[];
  v_key   text;
  v_ver   text;
  v_hash  text;
  v_app_version text;
  v_rec   record;
BEGIN
  -- Only process customer role registrations
  IF COALESCE(NEW.raw_user_meta_data->>'role', '') <> 'customer' THEN
    RETURN NEW;
  END IF;

  -- ---------------------------------------------------
  -- Step 0: Consent enforcement + acceptance records.
  -- Runs BEFORE any profile/customer writes so a refusal
  -- fails fast and rolls the whole sign-up back.
  --
  -- Staff who accepted on paper (admin onboarding) may
  -- bypass via 'legal_accepted_by_admin' = true.
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

      -- Idempotent: a repeat of the same version is a no-op.
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

    -- Every required document must actually be present.
    IF NOT (v_required <@ v_accepted) THEN
      RAISE EXCEPTION
        'Registration requires acceptance of the Terms of Service and Privacy Policy (missing: %)',
        array_to_string(v_required - v_accepted, ', ');
    END IF;
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

-- Step 5: Verify trigger still exists and is enabled
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

    RAISE NOTICE 'Step 5 ✅ Recreated trigger on_auth_user_created';
  ELSE
    RAISE NOTICE 'Step 5 ✅ Trigger on_auth_user_created already exists';
  END IF;
END $$;

-- Step 6: Self-documenting schema
COMMENT ON TABLE public.legal_acceptances IS
  'Legal consent evidence: one row per (user, document, version). '
  'Written by handle_new_auth_user() during customer registration and by '
  'LegalService when an existing user re-accepts in-app. document_hash is the '
  'sha256 of the exact asset text the user was shown.';

COMMENT ON COLUMN public.legal_acceptances.document_hash IS
  'sha256 hex digest of the document text displayed to the user, computed by '
  'lib/services/legal_service.dart from the bundled asset.';

COMMENT ON COLUMN public.legal_acceptances.source IS
  'registration = captured by the sign-up trigger; in_app_prompt = re-acceptance '
  'of a newer version by an already-registered user.';

-- =====================================================
-- Migration Complete!
-- =====================================================
-- Next steps:
-- 1. Run this against your Supabase project (SQL editor)
-- 2. Register a test customer WITHOUT consent -> rejected
-- 3. Register a test customer WITH consent -> profile,
--    customer AND two legal_acceptances rows created
-- 4. Verify the admin website supplies legal_acceptances
--    metadata for customer creation (see header note)
-- =====================================================

DO $$
BEGIN
  RAISE NOTICE '🎉 Migration completed successfully!';
  RAISE NOTICE 'legal_acceptances table + RLS policies are in place';
  RAISE NOTICE 'Customer registration now REQUIRES Terms of Service and Privacy Policy consent';
END $$;
