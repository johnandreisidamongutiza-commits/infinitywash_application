-- Migration: Add dismissed_at to orders table
-- Enables staff to dismiss / acknowledge rejected service requests
-- so they can clear notifications while retaining audit records.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS dismissed_at TIMESTAMPTZ NULL;

CREATE INDEX IF NOT EXISTS orders_dismissed_at_idx ON public.orders (dismissed_at);

