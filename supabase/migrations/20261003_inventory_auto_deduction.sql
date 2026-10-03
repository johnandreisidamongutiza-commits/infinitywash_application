-- =====================================================
-- Automatic Inventory Deduction on Order Completion
-- =====================================================
-- Purpose: Every time an order's status becomes 'completed'
--          (staff app, rider app, or admin web), chemicals
--          are silently deducted per wash load:
--            Liquid Bleach               15 ml / load
--            Liquid Detergent            30 ml / load
--            Liquid Fabric Conditioner   25 ml / load
--          Each deduction is logged in inventory_movements
--          as a 'consume' movement linked to the order.
-- Date:    2026-10-03
--
-- Design notes:
--   * Uses the EXISTING inventory_items and
--     inventory_movements tables. Only one column is added.
--   * usage_per_load (ml per load) is admin-editable.
--     Setting it to 0 disables auto-deduction for that item
--     (e.g., Commercial LPG Gas uses monthly manual refill).
--   * A database trigger is the "hidden process": it fires
--     no matter which client completes the order.
--   * Never blocks operations: if stock is insufficient,
--     the available amount is consumed and stock floors
--     at 0. The order still completes normally.
--   * Idempotent: only the transition INTO 'completed'
--     deducts. Re-saving a completed order deducts nothing.
-- =====================================================

-- -----------------------------------------------------
-- Step 1: Editable per-load consumption rate (ml/load)
-- -----------------------------------------------------
ALTER TABLE public.inventory_items
  ADD COLUMN IF NOT EXISTS usage_per_load numeric(12,3) NOT NULL DEFAULT 0;

ALTER TABLE public.inventory_items
  DROP CONSTRAINT IF EXISTS inventory_items_usage_per_load_check;

ALTER TABLE public.inventory_items
  ADD CONSTRAINT inventory_items_usage_per_load_check
  CHECK (usage_per_load >= 0);

COMMENT ON COLUMN public.inventory_items.usage_per_load IS
  'Milliliters consumed per wash load when an order completes. 0 disables auto-deduction for this item (e.g., LPG gas).';

-- -----------------------------------------------------
-- Step 2: Seed the chemical rates
-- (matched by item name so the item_code values do not
-- matter; LPG is left at 0 = no auto-deduction)
-- -----------------------------------------------------
UPDATE public.inventory_items SET usage_per_load = 15
WHERE item_name ILIKE '%bleach%';

UPDATE public.inventory_items SET usage_per_load = 30
WHERE item_name ILIKE '%detergent%';

UPDATE public.inventory_items SET usage_per_load = 25
WHERE item_name ILIKE '%fabric conditioner%' OR item_name ILIKE '%fabcon%';

-- -----------------------------------------------------
-- Step 3: Hidden deduction function
-- SECURITY DEFINER lets staff/rider sessions complete the
-- deduction even if RLS denies them direct writes to the
-- inventory tables; the logic itself is fixed server-side.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION public.deduct_inventory_for_completed_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_item     record;
  v_loads    integer;
  v_actor    uuid;
  v_wanted   numeric;
  v_deducted numeric;
BEGIN
  -- Fire only on the transition INTO 'completed'
  IF NEW.status IS DISTINCT FROM 'completed' THEN
    RETURN NEW;
  END IF;
  IF OLD.status = 'completed' THEN
    RETURN NEW; -- already completed: never deduct twice
  END IF;

  v_loads := COALESCE(NULLIF(NEW.loads_count, 0), 1);
  v_actor := auth.uid();

  BEGIN
    FOR v_item IN
      SELECT id, unit, usage_per_load, quantity
      FROM public.inventory_items
      WHERE status = 'active'
        AND usage_per_load > 0
      FOR UPDATE
    LOOP
      -- Convert ml into the item's stored unit (liters / 1000)
      v_wanted := CASE
        WHEN lower(v_item.unit) IN ('l', 'liter', 'litre', 'liters', 'litres')
          THEN v_item.usage_per_load * v_loads / 1000.0
        ELSE v_item.usage_per_load * v_loads
      END;

      -- Never block operations: consume only what is in stock
      -- (rounded to the column precision so the movement log
      -- always satisfies its quantity > 0 check)
      v_deducted := round(LEAST(v_wanted, v_item.quantity), 3);

      IF v_deducted > 0 THEN
        UPDATE public.inventory_items
           SET quantity = quantity - v_deducted
         WHERE id = v_item.id;

        INSERT INTO public.inventory_movements
          (inventory_item_id, movement_type, quantity,
           previous_quantity, new_quantity, order_id, performed_by)
        VALUES
          (v_item.id, 'consume', v_deducted,
           v_item.quantity, v_item.quantity - v_deducted,
           NEW.id, v_actor);
      END IF;
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    -- Inventory problems must never fail an order completion
    RAISE WARNING 'Auto inventory deduction skipped for order %: % (SQLSTATE %)',
      NEW.id, SQLERRM, SQLSTATE;
  END;

  RETURN NEW;
END;
$$;

-- -----------------------------------------------------
-- Step 4: Fire the deduction whenever orders.status changes
-- -----------------------------------------------------
DROP TRIGGER IF EXISTS trg_orders_deduct_inventory ON public.orders;

CREATE TRIGGER trg_orders_deduct_inventory
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.deduct_inventory_for_completed_order();

GRANT EXECUTE ON FUNCTION public.deduct_inventory_for_completed_order()
  TO authenticated;

COMMENT ON FUNCTION public.deduct_inventory_for_completed_order() IS
  'Hidden process: deducts chemical inventory per wash load when an order completes. Consumes only available stock and never blocks order completion.';

-- =====================================================
-- Migration Complete!
-- =====================================================
-- Next steps:
-- 1. Run this against your Supabase project (SQL editor)
-- 2. Test (full checklist in INVENTORY_AUTO_DEDUCTION.md):
--      UPDATE orders SET status = 'completed' WHERE id = '<test-order-id>';
--      SELECT item_name, quantity, usage_per_load FROM inventory_items;
--      SELECT * FROM inventory_movements ORDER BY created_at DESC LIMIT 10;
-- =====================================================

DO $$
BEGIN
  RAISE NOTICE '🎉 Migration completed successfully!';
  RAISE NOTICE 'Auto inventory deduction is live (15/30/25 ml per load).';
END $$;
