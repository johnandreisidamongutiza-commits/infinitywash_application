-- Persist announcement read receipts using the app's Supabase identity.
-- The mobile app does not authenticate with Firebase Auth, so Firestore
-- security rules cannot securely authorize notification_reads writes.

create table if not exists public.announcement_reads (
  user_id uuid not null references auth.users(id) on delete cascade,
  announcement_id text not null,
  read_at timestamptz not null default now(),
  constraint announcement_reads_pkey primary key (user_id, announcement_id)
);

alter table public.announcement_reads enable row level security;

grant select, insert, update, delete on public.announcement_reads to authenticated;

drop policy if exists "Users can read their announcement receipts"
  on public.announcement_reads;
create policy "Users can read their announcement receipts"
  on public.announcement_reads
  for select to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can create their announcement receipts"
  on public.announcement_reads;
create policy "Users can create their announcement receipts"
  on public.announcement_reads
  for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can update their announcement receipts"
  on public.announcement_reads;
create policy "Users can update their announcement receipts"
  on public.announcement_reads
  for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete their announcement receipts"
  on public.announcement_reads;
create policy "Users can delete their announcement receipts"
  on public.announcement_reads
  for delete to authenticated
  using (auth.uid() = user_id);

notify pgrst, 'reload schema';
