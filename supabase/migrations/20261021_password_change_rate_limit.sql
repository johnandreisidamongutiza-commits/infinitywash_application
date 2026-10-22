-- Server-only audit/rate-limit log for authenticated password changes.
create table if not exists public.password_change_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.password_change_attempts enable row level security;
revoke all on public.password_change_attempts from anon, authenticated;
create index if not exists password_change_attempts_user_created_idx
  on public.password_change_attempts (user_id, created_at desc);
