-- Rollback Migration: Add discount_amount and free_loads_redeemed to orders
-- Date: 2026-11-21

DROP INDEX IF EXISTS public.orders_free_loads_redeemed_idx;

ALTER TABLE public.orders
  DROP COLUMN IF EXISTS discount_amount,
  DROP COLUMN IF EXISTS free_loads_redeemed;
