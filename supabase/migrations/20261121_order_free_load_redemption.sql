-- Migration: Add discount_amount and free_loads_redeemed to orders
-- Date: 2026-11-21
-- Description:
--   Tracks free load loyalty redemptions and discounts directly on order records,
--   allowing receipts and reports to reflect gross subtotal, applied discounts, and net total.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS discount_amount NUMERIC(10, 2) DEFAULT 0.00,
  ADD COLUMN IF NOT EXISTS free_loads_redeemed INT DEFAULT 0;

CREATE INDEX IF NOT EXISTS orders_free_loads_redeemed_idx ON public.orders (free_loads_redeemed);
