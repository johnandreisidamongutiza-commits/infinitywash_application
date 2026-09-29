-- =====================================================
-- Fix Customer Code Column Type (with view handling)
-- =====================================================
-- Purpose: Change customer_code from integer to text
--          Handles dependent view vw_rfid_loyalty_cards
-- Date: 2026-09-29
-- =====================================================

-- Step 1: Save the view definition
DO $$
DECLARE
  view_definition TEXT;
BEGIN
  SELECT pg_get_viewdef('vw_rfid_loyalty_cards', true) INTO view_definition;
  RAISE NOTICE 'Saved view definition: %', view_definition;
END $$;

-- Step 2: Drop the dependent view temporarily
DROP VIEW IF EXISTS vw_rfid_loyalty_cards CASCADE;
RAISE NOTICE '✅ Dropped view vw_rfid_loyalty_cards';

-- Step 3: Alter the column type from integer to text
ALTER TABLE public.customers 
ALTER COLUMN customer_code TYPE TEXT;
RAISE NOTICE '✅ Changed customer_code to TEXT type';

-- Step 4: Recreate the view with the original definition
CREATE OR REPLACE VIEW vw_rfid_loyalty_cards AS
SELECT 
  card.id AS card_id,
  card.uid,
  card.status AS card_status,
  card.customer_id,
  CASE
    WHEN c.id IS NOT NULL THEN COALESCE(NULLIF(TRIM(BOTH FROM (c.first_name::text || ' '::text) || c.last_name::text), ''::text), c.customer_code::text, 'Customer #'::text || c.id)
    ELSE 'Unassigned'::text
  END AS owner_name,
  c.phone AS owner_phone,
  c.email AS owner_email,
  c.customer_type,
  c.status AS customer_status,
  c.customer_code,
  card.total_orders,
  card.total_loads,
  card.points_balance,
  card.created_at AS card_created_at,
  card.updated_at AS card_updated_at,
  p.username AS account_username,
  p.email AS account_email,
  p.role AS account_role
FROM rfid_loyalty_cards card
LEFT JOIN customers c ON card.customer_id = c.id
LEFT JOIN profiles p ON c.profile_id = p.id;

RAISE NOTICE '✅ Recreated view vw_rfid_loyalty_cards';

-- Step 5: Verify the change
DO $$
DECLARE
  new_type TEXT;
BEGIN
  SELECT data_type INTO new_type
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'customers'
    AND column_name = 'customer_code';
  
  RAISE NOTICE '🎉 Migration complete! customer_code type is now: %', new_type;
END $$;
