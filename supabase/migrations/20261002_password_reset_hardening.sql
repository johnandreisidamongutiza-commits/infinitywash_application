-- ============================================================================
-- Migration: Password reset hardening
-- Date:      2026-10-02
--
-- What this does
--   1. Ensures password_reset_tokens exists with the expected columns.
--   2. Enables ROW LEVEL SECURITY and adds NO policies for anon/authenticated
--      => clients can neither read nor write reset tokens. All token handling
--         happens in the `password-reset` Edge Function using the service role
--         key, which bypasses RLS by design.
--   3. Drops the legacy reset_user_password RPC. It trusted a user_id supplied
--      by the client, letting anyone reset any account's password.
--   4. Adds supporting indexes for the function's rate-limit and lookup paths.
--
-- Run with: supabase db push   (or paste into the SQL editor)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Table (idempotent) — matches what the Edge Function expects.
-- ---------------------------------------------------------------------------
create table if not exists public.password_reset_tokens (
  id         uuid primary key default gen_random_uuid(),
  email      text        not null,
  code_hash  text        not null,
  expires_at timestamptz not null,
  sent_at    timestamptz,
  attempts   integer     not null default 0,
  used       boolean     not null default false,
  created_at timestamptz not null default now()
);

-- Backfill columns if the table predates this migration.
alter table public.password_reset_tokens
  add column if not exists code_hash  text;
alter table public.password_reset_tokens
  add column if not exists expires_at timestamptz;
alter table public.password_reset_tokens
  add column if not exists sent_at    timestamptz;
alter table public.password_reset_tokens
  add column if not exists attempts   integer not null default 0;
alter table public.password_reset_tokens
  add column if not exists used       boolean not null default false;
alter table public.password_reset_tokens
  add column if not exists created_at timestamptz not null default now();

-- ---------------------------------------------------------------------------
-- 2. Lock it down: RLS on, zero client policies.
--    The service role (Edge Functions) bypasses RLS; nobody else gets access.
-- ---------------------------------------------------------------------------
alter table public.password_reset_tokens enable row level security;

-- Remove any permissive policies that may exist from earlier manual setup,
-- so the effective state is "no client access" regardless of history.
drop policy if exists "allow anon select password_reset_tokens"  on public.password_reset_tokens;
drop policy if exists "allow anon insert password_reset_tokens"  on public.password_reset_tokens;
drop policy if exists "allow anon update password_reset_tokens"  on public.password_reset_tokens;
drop policy if exists "allow anon delete password_reset_tokens"  on public.password_reset_tokens;
drop policy if exists "allow all password_reset_tokens"          on public.password_reset_tokens;
drop policy if exists "password_reset_tokens_select"             on public.password_reset_tokens;
drop policy if exists "password_reset_tokens_insert"             on public.password_reset_tokens;
drop policy if exists "password_reset_tokens_update"             on public.password_reset_tokens;
drop policy if exists "password_reset_tokens_delete"             on public.password_reset_tokens;

-- Revoke any direct grants that bypass RLS semantics.
revoke all on public.password_reset_tokens from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Drop the legacy client-trusting RPC if it exists.
--    Signature per the old client: (user_id uuid, new_password text,
--    reset_token_id uuid). Any variant is removed.
-- ---------------------------------------------------------------------------
drop function if exists public.reset_user_password(uuid, text, uuid);
drop function if exists public.reset_user_password(text, text, uuid);

-- ---------------------------------------------------------------------------
-- 4. Indexes used by the Edge Function.
-- ---------------------------------------------------------------------------
create index if not exists password_reset_tokens_email_created_idx
  on public.password_reset_tokens (email, created_at desc);
create index if not exists password_reset_tokens_used_idx
  on public.password_reset_tokens (email, used);

-- ---------------------------------------------------------------------------
-- 5. Housekeeping: purge tokens older than 1 day (manual/detached cron).
--    Optional scheduled job, safe to run repeatedly:
--      select cron.schedule('purge-reset-tokens', '0 3 * * *',
--        $$delete from public.password_reset_tokens where expires_at < now() - interval '1 day'$$);
-- ---------------------------------------------------------------------------
