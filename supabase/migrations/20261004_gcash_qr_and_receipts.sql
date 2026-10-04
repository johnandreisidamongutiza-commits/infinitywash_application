-- =====================================================
-- GCash QR + Payment Receipt Upload
-- =====================================================
-- Purpose: Supports the mobile app's GCash payment flow:
--   * The admin website uploads the GCash QR image and the GCash
--     account name/number into the gcash_settings table
--     (singleton row, id = 1). The app reads that row to show the
--     same QR the website displays.
--   * Staff/customer see that QR, pay, then capture/upload the
--     GCash receipt image into the 'payment-receipts' bucket.
--   * The payments row is created with status 'pending' — that
--     is the FOR REVIEW state the admin website's OCR pipeline
--     uses (it extracts the reference number from the receipt,
--     matches it against the daily transaction history, then
--     marks the payment VERIFIED or rejects it).
--   * The order is marked payment_status='paid' immediately so
--     the mobile app reflects the payment right away.
-- Date:    2026-10-04
--
-- Idempotent: safe to run more than once.
-- =====================================================

-- -----------------------------------------------------
-- Step 1: Receipt image URL on payments
-- -----------------------------------------------------
ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS receipt_url text;

COMMENT ON COLUMN public.payments.receipt_url IS
  'Public URL of the GCash payment receipt image uploaded from the mobile app. reference_number is filled later by admin OCR matching.';

-- -----------------------------------------------------
-- Step 2: Guarantee columns the mobile Dart model reads
-- (models/order.dart serializes payment_method and paid_at
-- on orders; add them if they are missing on this DB)
-- -----------------------------------------------------
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS payment_method varchar(30);

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS paid_at timestamptz;

-- -----------------------------------------------------
-- Step 3: Storage bucket for payment receipts
-- Public read so the app and the admin website can display
-- / OCR the images without signed URLs.
-- -----------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
VALUES ('payment-receipts', 'payment-receipts', true)
ON CONFLICT (id) DO NOTHING;

-- -----------------------------------------------------
-- Step 4: Access policies for the bucket
-- -----------------------------------------------------
DROP POLICY IF EXISTS "payment_receipts_authenticated_insert" ON storage.objects;
CREATE POLICY "payment_receipts_authenticated_insert"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'payment-receipts');

DROP POLICY IF EXISTS "payment_receipts_authenticated_select" ON storage.objects;
CREATE POLICY "payment_receipts_authenticated_select"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'payment-receipts');

DROP POLICY IF EXISTS "payment_receipts_public_select" ON storage.objects;
CREATE POLICY "payment_receipts_public_select"
ON storage.objects FOR SELECT TO public
USING (bucket_id = 'payment-receipts');

-- -----------------------------------------------------
-- Step 5: GCash settings table (admin-managed QR + account
-- details). Created idempotently so fresh environments match
-- the admin website's schema; existing databases keep their
-- uploaded QR picture untouched.
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS public.gcash_settings (
  id integer not null default 1,
  qr_image_url text null,
  account_name character varying(120) null,
  account_number character varying(40) null,
  updated_at timestamp with time zone null,
  constraint gcash_settings_pkey primary key (id),
  constraint gcash_settings_id_check check ((id = 1))
);

COMMENT ON TABLE public.gcash_settings IS
  'Singleton row (id = 1) holding the GCash QR image URL and account details managed from the admin website and displayed on the mobile app payment screens.';

-- Ensure the singleton row exists (does not overwrite the admin's values)
INSERT INTO public.gcash_settings (id)
VALUES (1)
ON CONFLICT (id) DO NOTHING;

-- -----------------------------------------------------
-- Step 6: Make sure authenticated users can read
-- gcash_settings (only created when RLS is enabled and no
-- read policy exists yet)
-- -----------------------------------------------------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'gcash_settings'
      AND c.relrowsecurity = true
  )
  AND NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'gcash_settings'
      AND policyname = 'gcash_settings_authenticated_read'
  ) THEN
    CREATE POLICY "gcash_settings_authenticated_read"
    ON public.gcash_settings FOR SELECT TO authenticated
    USING (true);
  END IF;
END $$;

DO $$
BEGIN
  RAISE NOTICE '✅ GCash QR + payment receipt upload migration complete.';
END $$;
