-- Store customer-side OCR extraction and keep rejection details available
-- to the customer order screen.
ALTER TABLE public.gcash_receipt_submissions
  ADD COLUMN IF NOT EXISTS ocr_receipt_datetime text NULL,
  ADD COLUMN IF NOT EXISTS rejection_reason text NULL;

COMMENT ON COLUMN public.gcash_receipt_submissions.rejection_reason IS
  'Admin-provided explanation shown to the customer when a receipt is rejected.';
