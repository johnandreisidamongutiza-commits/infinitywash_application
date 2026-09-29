-- =====================================================
-- Customer Code Sequence Rollback
-- =====================================================
-- Purpose: Rollback the customer code sequence migration
-- Date: 2026-09-29
-- 
-- Run this script ONLY if you need to revert the changes
-- made by 20260929_customer_code_sequence.sql
-- =====================================================

-- Step 1: Drop the RPC function
DROP FUNCTION IF EXISTS get_next_customer_code();

-- Step 2: Drop the sequence
DROP SEQUENCE IF EXISTS customer_code_seq CASCADE;

-- Verification
DO $$
BEGIN
  RAISE NOTICE 'Customer code sequence and function have been removed.';
  RAISE NOTICE 'The application will fall back to the old query-based customer code generation.';
END $$;
