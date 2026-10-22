-- Track successful OTP delivery separately from attempted sends.
-- Existing rows default to false because their delivery outcome is unknown.
alter table public.password_reset_tokens
  add column if not exists email_sent boolean not null default false;

create index if not exists password_reset_tokens_email_sent_created_idx
  on public.password_reset_tokens (email, created_at desc)
  where email_sent = true;
