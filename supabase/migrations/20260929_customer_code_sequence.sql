-- =====================================================
-- Customer Code Sequence Migration
-- =====================================================
-- Purpose: Fix race conditions in customer code generation
-- Date: 2026-09-29
-- 
-- This migration creates a database sequence that generates
-- unique customer codes atomically, preventing duplicate key
-- violations when multiple customers register simultaneously.
-- =====================================================

-- Step 1: Create sequence for customer codes
-- Starts at 1, will be initialized to current max below
CREATE SEQUENCE IF NOT EXISTS customer_code_seq START WITH 1;

-- Step 2: Initialize sequence to current maximum customer number
-- This ensures new customers continue from where we left off
DO $$
DECLARE
  max_customer_num INTEGER;
BEGIN
  -- Extract the highest numeric part from existing customer codes
  SELECT COALESCE(MAX(CAST(SUBSTRING(customer_code FROM 6) AS INTEGER)), 0)
  INTO max_customer_num
  FROM customers
  WHERE customer_code ~ '^CUST-[0-9]{5}$';
  
  -- Set sequence to max + 1
  -- The 'false' parameter means the next nextval() will return max_customer_num + 1
  PERFORM setval('customer_code_seq', max_customer_num, true);
  
  RAISE NOTICE 'Customer code sequence initialized to % (next will be %)', 
    max_customer_num, max_customer_num + 1;
END $$;

-- Step 3: Create RPC function to generate next customer code
-- This function is called from the Flutter app via Supabase RPC
CREATE OR REPLACE FUNCTION get_next_customer_code()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER -- Run with elevated privileges
AS $$
DECLARE
  next_num INTEGER;
  customer_code TEXT;
BEGIN
  -- Get next sequence number
  next_num := nextval('customer_code_seq');
  
  -- Format as CUST-XXXXX (5 digits, padded with zeros)
  customer_code := 'CUST-' || LPAD(next_num::TEXT, 5, '0');
  
  RETURN customer_code;
END;
$$;

-- Step 4: Grant execute permission to authenticated users
-- This allows the Flutter app to call the function
GRANT EXECUTE ON FUNCTION get_next_customer_code() TO authenticated;
GRANT EXECUTE ON FUNCTION get_next_customer_code() TO anon;

-- Step 5: Add comment for documentation
COMMENT ON FUNCTION get_next_customer_code() IS 
  'Generates unique sequential customer codes using a database sequence. '
  'This prevents race conditions and duplicate key violations during concurrent customer creation.';

COMMENT ON SEQUENCE customer_code_seq IS
  'Sequence for generating unique customer code numbers. Used by get_next_customer_code() function.';

-- =====================================================
-- Verification Query (optional - for testing)
-- =====================================================
-- Run this to test the function:
-- SELECT get_next_customer_code();
-- SELECT get_next_customer_code();
-- SELECT get_next_customer_code();
-- 
-- Expected output:
-- CUST-00001 (or continues from your current max)
-- CUST-00002
-- CUST-00003
-- =====================================================
