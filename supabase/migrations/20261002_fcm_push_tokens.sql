-- =====================================================
-- FCM Push Tokens Migration
-- =====================================================
-- Purpose: Store one FCM token per device per user so the
--          backend can push notifications to every user
--          (customers, staff, riders) from an Edge Function.
-- Date: 2026-10-02
--
-- Security: RLS lets each user manage ONLY their own token
--           rows. The broadcast Edge Function uses the
--           service role key, which bypasses RLS by design.
-- =====================================================

-- Step 1: Tokens table
CREATE TABLE IF NOT EXISTS public.fcm_tokens (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL,              -- auth.users.id
  token       text   NOT NULL,
  platform    text   NOT NULL DEFAULT 'android'
              CHECK (platform IN ('android', 'ios', 'web')),
  created_at  timestamptz NOT NULL DEFAULT NOW(),
  updated_at  timestamptz NOT NULL DEFAULT NOW(),

  -- One row per (user, device). Re-registering overwrites in place.
  CONSTRAINT fcm_tokens_user_token_unique UNIQUE (user_id, token)
);

-- Step 2: Indexes for the broadcast lookup and sign-out cleanup
CREATE INDEX IF NOT EXISTS idx_fcm_tokens_user_id ON public.fcm_tokens (user_id);
CREATE INDEX IF NOT EXISTS idx_fcm_tokens_token   ON public.fcm_tokens (token);

-- Step 3: Row Level Security
ALTER TABLE public.fcm_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can insert own fcm tokens"  ON public.fcm_tokens;
DROP POLICY IF EXISTS "Users can select own fcm tokens"  ON public.fcm_tokens;
DROP POLICY IF EXISTS "Users can update own fcm tokens"  ON public.fcm_tokens;
DROP POLICY IF EXISTS "Users can delete own fcm tokens"  ON public.fcm_tokens;

CREATE POLICY "Users can insert own fcm tokens"
  ON public.fcm_tokens FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can select own fcm tokens"
  ON public.fcm_tokens FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Users can update own fcm tokens"
  ON public.fcm_tokens FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can delete own fcm tokens"
  ON public.fcm_tokens FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- Step 4: Housekeeping comment
COMMENT ON TABLE public.fcm_tokens IS
  'Firebase Cloud Messaging device tokens, one row per user per device. '
  'Written by the app on sign-in / token refresh; read by the '
  'send-push-notification Edge Function using the service role.';

-- =====================================================
-- Migration Complete!
-- =====================================================
-- Next steps:
-- 1. Run this against your Supabase project (SQL editor)
-- 2. Deploy the send-push-notification Edge Function:
--      supabase functions deploy send-push-notification
--      supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON='<service-account json>'
-- =====================================================

DO $$
BEGIN
  RAISE NOTICE '🎉 Migration completed successfully!';
  RAISE NOTICE 'fcm_tokens table ready with per-user RLS';
END $$;
