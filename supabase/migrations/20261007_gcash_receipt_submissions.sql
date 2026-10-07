-- =====================================================
-- Migration: GCash Receipt Submissions Table & RLS Policies
-- =====================================================
-- Purpose: Holds GCash receipt submissions for OCR processing,
--          admin review, and transaction verification.
-- Links:   orders (order_id), payments (payment_id), profiles (submitted_by, verified_by)
-- =====================================================

CREATE TABLE IF NOT EXISTS public.gcash_receipt_submissions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  order_id uuid NULL,
  order_number character varying(40) NULL,
  receipt_image_url text NOT NULL,
  image_size_bytes integer NULL,
  ocr_raw_text text NULL,
  ocr_reference_number character varying(120) NULL,
  ocr_amount numeric(12, 2) NULL,
  ocr_success boolean NOT NULL DEFAULT false,
  ocr_error text NULL,
  match_status character varying(20) NOT NULL DEFAULT 'no_match'::character varying,
  match_detail text NULL,
  status character varying(20) NOT NULL DEFAULT 'pending_review'::character varying,
  source character varying(20) NOT NULL DEFAULT 'admin_upload'::character varying,
  submitted_by uuid NULL,
  verified_by uuid NULL,
  verified_at timestamp with time zone NULL,
  rejection_reason text NULL,
  payment_id uuid NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NULL,
  CONSTRAINT gcash_receipt_submissions_pkey PRIMARY KEY (id),
  CONSTRAINT gcash_receipt_submissions_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders (id) ON DELETE SET NULL,
  CONSTRAINT gcash_receipt_submissions_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES public.payments (id) ON DELETE SET NULL,
  CONSTRAINT gcash_receipt_submissions_submitted_by_fkey FOREIGN KEY (submitted_by) REFERENCES public.profiles (id) ON DELETE SET NULL,
  CONSTRAINT gcash_receipt_submissions_verified_by_fkey FOREIGN KEY (verified_by) REFERENCES public.profiles (id) ON DELETE SET NULL
);

-- Ensure default UUID generation if table was created without it
ALTER TABLE public.gcash_receipt_submissions 
  ALTER COLUMN id SET DEFAULT gen_random_uuid();

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_gcash_submissions_status 
  ON public.gcash_receipt_submissions USING btree (status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_gcash_submissions_order 
  ON public.gcash_receipt_submissions USING btree (order_id);

CREATE INDEX IF NOT EXISTS idx_gcash_submissions_payment 
  ON public.gcash_receipt_submissions USING btree (payment_id);

-- -----------------------------------------------------
-- Row Level Security (RLS)
-- -----------------------------------------------------
ALTER TABLE public.gcash_receipt_submissions ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users (customers, riders, staff) to insert receipt submissions
DROP POLICY IF EXISTS "gcash_submissions_authenticated_insert" ON public.gcash_receipt_submissions;
CREATE POLICY "gcash_submissions_authenticated_insert"
ON public.gcash_receipt_submissions FOR INSERT TO authenticated
WITH CHECK (true);

-- Allow authenticated users to read receipt submissions
DROP POLICY IF EXISTS "gcash_submissions_authenticated_select" ON public.gcash_receipt_submissions;
CREATE POLICY "gcash_submissions_authenticated_select"
ON public.gcash_receipt_submissions FOR SELECT TO authenticated
USING (true);

-- Allow authenticated staff/admin to update receipt submissions (for OCR/review)
DROP POLICY IF EXISTS "gcash_submissions_authenticated_update" ON public.gcash_receipt_submissions;
CREATE POLICY "gcash_submissions_authenticated_update"
ON public.gcash_receipt_submissions FOR UPDATE TO authenticated
USING (true)
WITH CHECK (true);
