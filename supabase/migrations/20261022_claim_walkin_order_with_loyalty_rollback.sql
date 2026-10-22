-- =========================================================================
-- Rollback Migration: Claim Walk-in Orders with RFID Loyalty Points Integration
-- Date: 2026-10-22
-- =========================================================================

DROP FUNCTION IF EXISTS claim_walkin_order(TEXT, TEXT, UUID);
DROP FUNCTION IF EXISTS find_unclaimed_walkin_orders(TEXT);
DROP FUNCTION IF EXISTS normalize_ph_phone(TEXT);
