-- =====================================================
-- FCM Push Tokens Rollback Migration
-- =====================================================
-- Purpose: Drop the fcm_tokens table and its policies.
-- Run this ONLY if you need to undo 20261002_fcm_push_tokens.sql
-- Date: 2026-10-02
-- =====================================================

DROP TABLE IF EXISTS public.fcm_tokens;

DO $$
BEGIN
  RAISE NOTICE '🎉 Rollback completed successfully!';
  RAISE NOTICE 'fcm_tokens table dropped';
END $$;
