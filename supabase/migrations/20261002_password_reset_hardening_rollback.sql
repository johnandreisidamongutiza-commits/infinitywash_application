-- ============================================================================
-- Rollback of 20261002_password_reset_hardening.sql
--
-- Restores the pre-hardening behaviour: clients can read/write reset tokens
-- and the legacy reset_user_password RPC is available again. Only use this if
-- you need to revert to the old (INSECURE) flow.
-- ============================================================================

-- Recreate the legacy RPC (signature used by the old Flutter client).
-- WARNING: this trusts a client-supplied user_id and is vulnerable.
create or replace function public.reset_user_password(
  p_user_id uuid,
  p_new_password text,
  p_reset_token_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Minimal re-implementation: only updates auth.users via the extension.
  -- If pg_auth is unavailable in your project, contact support instead.
  update auth.users
     set encrypted_password =
           crypt(p_new_password, gen_salt('bf'))
   where id = p_user_id;
end;
$$;

grant execute on function public.reset_user_password(uuid, text, uuid) to anon, authenticated;

-- Re-open the table to clients (as before).
create policy "allow anon select password_reset_tokens"
  on public.password_reset_tokens for select to anon using (true);
create policy "allow anon update password_reset_tokens"
  on public.password_reset_tokens for update to anon using (true);

revoke all on public.password_reset_tokens from anon, authenticated;
grant select, update on public.password_reset_tokens to anon, authenticated;
