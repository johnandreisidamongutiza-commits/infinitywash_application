-- =====================================================
-- Rollback: GCash QR + Payment Receipt Upload
-- =====================================================
-- Purpose: Removes the receipt upload schema, the storage
--          bucket and the gcash_settings read policy.
-- Date:    2026-10-04
-- =====================================================

-- Step 1: Remove the receipt URL column
-- (files already stored in the bucket are intentionally KEPT;
-- delete the bucket objects manually if a full purge is needed)
ALTER TABLE public.payments
  DROP COLUMN IF EXISTS receipt_url;

-- Step 2: Remove the bucket policies
DROP POLICY IF EXISTS "payment_receipts_authenticated_insert" ON storage.objects;
DROP POLICY IF EXISTS "payment_receipts_authenticated_select" ON storage.objects;
DROP POLICY IF EXISTS "payment_receipts_public_select" ON storage.objects;

-- Step 3: Remove the bucket itself
DELETE FROM storage.buckets WHERE id = 'payment-receipts';

-- Step 4: Remove the gcash_settings read policy.
-- The gcash_settings TABLE itself is intentionally KEPT (it holds
-- the admin's uploaded QR picture); drop it manually only if the
-- whole GCash configuration should be removed.
DROP POLICY IF EXISTS "gcash_settings_authenticated_read" ON public.gcash_settings;

-- orders.payment_method / paid_at are intentionally KEPT:
-- the Dart model (models/order.dart) already reads them.

DO $$
BEGIN
  RAISE NOTICE '✅ Rollback complete: GCash QR + receipt upload removed.';
END $$;
