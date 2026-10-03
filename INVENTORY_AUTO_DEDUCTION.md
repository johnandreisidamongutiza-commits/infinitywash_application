# Automatic Inventory Deduction on Order Completion

Every time an order is marked **done/completed**, the database silently deducts
laundry chemicals per wash load. This is a **hidden process** — nothing appears
in the staff or customer app, and it works no matter which side completes the
order (staff app, rider app, or admin web).

## What gets deducted

| Item                       | Default rate      | Deducted amount (2-load order) |
| -------------------------- | ----------------- | ------------------------------ |
| Liquid Bleach              | 15 ml per load    | 30 ml                          |
| Liquid Detergent           | 30 ml per load    | 60 ml                          |
| Liquid Fabric Conditioner  | 25 ml per load    | 50 ml                          |
| Commercial LPG Gas         | 0 (disabled)      | — (manual monthly refill)      |

Amount = `usage_per_load × orders.loads_count`.

## How it works

- **No new table.** Uses the existing `inventory_items` (balances) and
  `inventory_movements` (history) tables. One column was added:
  - `inventory_items.usage_per_load numeric(12,3)` — milliliters consumed per
    wash load. `0` disables auto-deduction for that item.
- **Database trigger** `trg_orders_deduct_inventory` on `orders`:
  fires only when `status` transitions into `'completed'`.
- Each deduction writes a `consume` row in `inventory_movements` with the
  `order_id` and `performed_by` = the profile who completed the order, so the
  admin can audit exactly which order used which chemicals.
- The function is `SECURITY DEFINER`, so the deduction also works when a
  staff/rider session lacks direct write access to inventory tables. The
  deduction logic is fixed server-side and cannot be tampered with from a client.

## Safety behavior

1. **Never blocks operations.** If an item has less stock than needed, only the
   available amount is consumed and the quantity floors at 0. The order still
   completes normally.
2. **Idempotent.** Only the transition into `completed` deducts. Re-saving or
   re-syncing an already-completed order deducts nothing.
3. **Resilient.** If anything unexpected fails during deduction, the order
   completion still succeeds (a warning is logged and no deduction is applied
   for that order).
4. **Unit-aware.** If an item's `unit` is liters (`l`, `liter`, …), the ml rate
   is divided by 1000 automatically. Otherwise the rate is applied as-is (ml).

## Editing the rates (admin)

Change any rate with one line in the Supabase SQL editor — it takes effect on
the next completed order:

```sql
UPDATE inventory_items SET usage_per_load = 40 WHERE item_name ILIKE '%detergent%';
-- Disable auto-deduction for an item:
UPDATE inventory_items SET usage_per_load = 0 WHERE item_name ILIKE '%bleach%';
-- Check current rates and stock:
SELECT item_name, unit, quantity, usage_per_load FROM inventory_items;
```

The admin web can also expose this later by adding a "Usage per load (ml)"
field to its edit-supply form that writes to `inventory_items.usage_per_load`.

## Deployment

1. Open the Supabase SQL editor and run
   `supabase/migrations/20261003_inventory_auto_deduction.sql`.
2. To undo everything (keeps movement history), run
   `supabase/migrations/20261003_inventory_auto_deduction_rollback.sql`.

No Flutter app changes are required — the staff "Mark as Complete" flow and the
rider `delivery_done` sync already update `orders.status`, which the trigger
listens to.

## Test checklist (Supabase SQL editor)

```sql
-- 1. Note the current stock and rates
SELECT item_name, quantity, usage_per_load FROM inventory_items;

-- 2. Complete a test order (prefer one with loads_count = 2 to verify multiplication)
SELECT id, order_number, loads_count FROM orders ORDER BY created_at DESC LIMIT 5;
UPDATE orders SET status = 'completed' WHERE id = '<test-order-id>';

-- 3. Verify: stock dropped by 15/30/25 × loads, and one 'consume' movement
--    per chemical appeared, linked to the order
SELECT item_name, quantity FROM inventory_items;
SELECT * FROM inventory_movements ORDER BY created_at DESC LIMIT 10;

-- 4. Idempotency: run the UPDATE again — no new movements, no extra deduction

-- 5. Empty stock: set an item to 0, complete another order — the order still
--    completes, that item stays at 0, movements appear only for the others
UPDATE inventory_items SET quantity = 0 WHERE item_name ILIKE '%bleach%';

-- 6. Editable rate: change a rate, complete an order, confirm the new rate is used
```

## Known limitations

- A completed order that is later **cancelled** does not restore chemicals
  (no reversal movement). Can be added later if needed.
- Orders **created directly** with `status = 'completed'` (instead of being
  updated into it) do not deduct — normal intake never does this.
- LPG gas is intentionally excluded (monthly manual refill per the admin design).
