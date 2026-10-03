-- =====================================================
-- Rollback: Automatic Inventory Deduction
-- =====================================================
-- Purpose: Safely removes the auto-deduction trigger, its
--          function, and the usage_per_load column.
--          inventory_movements history is KEPT — only the
--          automatic deduction behavior is removed.
-- Date:    2026-10-03
-- =====================================================

-- Step 1: Remove the trigger
DROP TRIGGER IF EXISTS trg_orders_deduct_inventory ON public.orders;

-- Step 2: Remove the function
DROP FUNCTION IF EXISTS public.deduct_inventory_for_completed_order();

-- Step 3: Remove the editable per-load rate column
-- (the seeded 15/30/25 ml values go with it; re-run the
-- main migration to restore)
ALTER TABLE public.inventory_items
  DROP COLUMN IF EXISTS usage_per_load;

-- =====================================================
-- Rollback Complete!
-- =====================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Rollback complete: auto inventory deduction removed.';
END $$;
