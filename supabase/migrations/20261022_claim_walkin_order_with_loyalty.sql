-- =========================================================================
-- Migration: Claim Walk-in Orders with RFID Loyalty Points Integration
-- Date: 2026-10-22
-- Description:
--   Allows customers with registered app accounts to transfer walk-in orders
--   created at the physical shop into their mobile app account.
--   Preserves load breakdowns and automatically credits any unawarded loyalty
--   points if the order was already completed and customer has an active card.
-- =========================================================================

-- Helper function to normalize Philippine phone numbers to 10 digits (9XXXXXXXXX)
CREATE OR REPLACE FUNCTION normalize_ph_phone(raw_phone TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  digits TEXT;
BEGIN
  IF raw_phone IS NULL OR raw_phone = '' THEN
    RETURN '';
  END IF;

  -- Strip all non-digit characters
  digits := regexp_replace(raw_phone, '[^\d]', '', 'g');

  -- If 11 digits starting with 09 (e.g. 09171234567), strip leading 0
  IF length(digits) = 11 AND digits LIKE '09%' THEN
    digits := substring(digits FROM 2);
  -- If 12 digits starting with 639 (e.g. 639171234567), strip leading 63
  ELSIF length(digits) = 12 AND digits LIKE '639%' THEN
    digits := substring(digits FROM 3);
  END IF;

  RETURN digits;
END;
$$;

-- Function: Find unclaimed walk-in orders matching a phone number
CREATE OR REPLACE FUNCTION find_unclaimed_walkin_orders(p_phone TEXT)
RETURNS TABLE (
  order_id UUID,
  order_number TEXT,
  service_name TEXT,
  loads_count INT,
  weight_kg NUMERIC,
  total_amount NUMERIC,
  order_status TEXT,
  payment_status TEXT,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  norm_phone TEXT;
BEGIN
  norm_phone := normalize_ph_phone(p_phone);
  IF norm_phone = '' THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    o.id AS order_id,
    o.order_number,
    o.service_name,
    COALESCE(o.loads_count, 1) AS loads_count,
    COALESCE(o.weight_kg, 0) AS weight_kg,
    COALESCE(o.total_amount, 0) AS total_amount,
    o.status AS order_status,
    o.payment_status,
    o.created_at
  FROM orders o
  JOIN customers c ON o.customer_id = c.id
  WHERE c.profile_id IS NULL -- Must be an unlinked walk-in customer
    AND (
      normalize_ph_phone(c.phone) = norm_phone
      OR normalize_ph_phone(o.delivery_address) = norm_phone
    )
    AND o.created_at >= (NOW() - INTERVAL '30 days')
  ORDER BY o.created_at DESC;
END;
$$;

-- Function: Claim a walk-in order and associate it with target customer profile
CREATE OR REPLACE FUNCTION claim_walkin_order(
  p_order_number TEXT,
  p_verification_phone TEXT,
  p_target_customer_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_target_customer RECORD;
  v_order RECORD;
  v_order_customer RECORD;
  v_clean_order_num TEXT;
  v_norm_order_phone TEXT;
  v_norm_input_phone TEXT;
  v_norm_target_phone TEXT;
  v_phone_matched BOOLEAN := FALSE;
  v_card RECORD;
  v_points_awarded INT := 0;
  v_already_has_points BOOLEAN := FALSE;
BEGIN
  v_clean_order_num := TRIM(p_order_number);
  IF v_clean_order_num = '' THEN
    RAISE EXCEPTION 'Order number is required.';
  END IF;

  -- 1. Verify target customer exists and has an app profile
  SELECT id, profile_id, phone, first_name, last_name
  INTO v_target_customer
  FROM customers
  WHERE id = p_target_customer_id AND status = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Target customer profile not found or inactive.';
  END IF;

  IF v_target_customer.profile_id IS NULL THEN
    RAISE EXCEPTION 'Target customer must be an authenticated app customer.';
  END IF;

  -- 2. Lookup the order (by order_number or id prefix)
  SELECT
    o.id,
    o.order_number,
    o.customer_id,
    o.status,
    o.payment_status,
    COALESCE(o.loads_count, 1) AS loads_count,
    o.total_amount,
    o.created_at
  INTO v_order
  FROM orders o
  WHERE LOWER(TRIM(o.order_number)) = LOWER(v_clean_order_num)
     OR o.id::TEXT = LOWER(v_clean_order_num)
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found. Please verify the order number from your receipt.';
  END IF;

  -- 3. Check current ownership of the order
  SELECT id, profile_id, phone, customer_type
  INTO v_order_customer
  FROM customers
  WHERE id = v_order.customer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order customer record missing.';
  END IF;

  -- Check if already claimed by this user
  IF v_order.customer_id = p_target_customer_id THEN
    RAISE EXCEPTION 'This order is already linked to your account.';
  END IF;

  -- Check if already claimed by another registered user
  IF v_order_customer.profile_id IS NOT NULL THEN
    RAISE EXCEPTION 'This order has already been linked to an existing account.';
  END IF;

  -- 4. Verify Phone Number (Must match walk-in record or target user phone)
  v_norm_order_phone := normalize_ph_phone(v_order_customer.phone);
  v_norm_input_phone := normalize_ph_phone(p_verification_phone);
  v_norm_target_phone := normalize_ph_phone(v_target_customer.phone);

  IF v_norm_order_phone <> '' AND (
    v_norm_order_phone = v_norm_input_phone
    OR v_norm_order_phone = v_norm_target_phone
  ) THEN
    v_phone_matched := TRUE;
  ELSIF v_norm_order_phone = '' AND v_norm_input_phone = v_norm_target_phone THEN
    -- If staff did not record a phone at the counter, allow claim if user confirmed
    v_phone_matched := TRUE;
  END IF;

  IF NOT v_phone_matched THEN
    RAISE EXCEPTION 'Verification failed. The phone number provided does not match the shop counter record.';
  END IF;

  -- 5. Transfer order to target customer
  UPDATE orders
  SET customer_id = p_target_customer_id,
      updated_at = NOW()
  WHERE id = v_order.id;

  -- 6. RFID Loyalty Points handling:
  -- If order was already completed, check if points should be retroactively credited
  IF v_order.status = 'completed' AND v_order.loads_count > 0 THEN
    -- Check if points were already awarded for this order
    SELECT EXISTS (
      SELECT 1 FROM loyalty_points_history
      WHERE order_id = v_order.id AND transaction_type = 'earned'
    ) INTO v_already_has_points;

    IF NOT v_already_has_points THEN
      -- Find active loyalty card linked to target customer
      SELECT id, uid, points_balance, total_orders, total_loads
      INTO v_card
      FROM rfid_loyalty_cards
      WHERE customer_id = p_target_customer_id AND status = 'active'
      ORDER BY created_at ASC
      LIMIT 1;

      IF FOUND THEN
        v_points_awarded := v_order.loads_count;

        -- Update card balance
        UPDATE rfid_loyalty_cards
        SET points_balance = points_balance + v_points_awarded,
            total_loads = total_loads + v_points_awarded,
            total_orders = total_orders + 1,
            updated_at = NOW()
        WHERE id = v_card.id;

        -- Record ledger entry
        INSERT INTO loyalty_points_history (
          card_id,
          customer_id,
          order_id,
          transaction_type,
          points,
          loads_count,
          discount_amount,
          description,
          created_at
        ) VALUES (
          v_card.id,
          v_target_customer.profile_id,
          v_order.id,
          'earned',
          v_points_awarded,
          v_points_awarded,
          0.00,
          'Earned ' || v_points_awarded || ' pt(s) from claimed walk-in order ' || COALESCE(v_order.order_number, ''),
          NOW()
        );
      END IF;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', v_order.id,
    'order_number', v_order.order_number,
    'status', v_order.status,
    'loads_count', v_order.loads_count,
    'points_awarded', v_points_awarded,
    'message', 'Order ' || COALESCE(v_order.order_number, '') || ' successfully linked to your account.'
  );
END;
$$;

-- Grant execution permissions
GRANT EXECUTE ON FUNCTION normalize_ph_phone(TEXT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION find_unclaimed_walkin_orders(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION claim_walkin_order(TEXT, TEXT, UUID) TO authenticated;
