-- Run this once in Supabase Dashboard -> SQL Editor.
-- It creates the customer profile immediately, even when email confirmation
-- prevents the mobile app from receiving a session after registration.

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if coalesce(new.raw_user_meta_data ->> 'role', '') <> 'customer' then
    return new;
  end if;

  insert into public.profiles (
    id,
    supabase_user_id,
    first_name,
    last_name,
    email,
    phone,
    address,
    landmark,
    role,
    status,
    created_at,
    updated_at
  )
  values (
    new.id,
    new.id,
    new.raw_user_meta_data ->> 'first_name',
    new.raw_user_meta_data ->> 'last_name',
    new.email,
    coalesce(new.phone, new.raw_user_meta_data ->> 'phone'),
    new.raw_user_meta_data ->> 'address',
    new.raw_user_meta_data ->> 'landmark',
    'customer',
    'active',
    coalesce(new.created_at, now()),
    now()
  )
  on conflict (id) do update set
    supabase_user_id = excluded.supabase_user_id,
    first_name = excluded.first_name,
    last_name = excluded.last_name,
    email = excluded.email,
    phone = excluded.phone,
    address = excluded.address,
    landmark = excluded.landmark,
    role = excluded.role,
    status = excluded.status,
    updated_at = now();

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

-- Replace recursive profiles policies with policies that only compare the
-- current row to the authenticated user's ID.
do $$
declare
  policy_record record;
begin
  for policy_record in
    select policyname
    from pg_policies
    where schemaname = 'public' and tablename = 'profiles'
  loop
    execute format('drop policy if exists %I on public.profiles', policy_record.policyname);
  end loop;
end;
$$;

alter table public.profiles enable row level security;

create policy "Users can read their own profile"
on public.profiles for select
to authenticated
using (supabase_user_id = auth.uid());

create policy "Users can create their own profile"
on public.profiles for insert
to authenticated
with check (supabase_user_id = auth.uid());

create policy "Users can update their own profile"
on public.profiles for update
to authenticated
using (supabase_user_id = auth.uid())
with check (supabase_user_id = auth.uid());

alter table public.employees enable row level security;

drop policy if exists "Employees can read their own employee record" on public.employees;

create policy "Employees can read their own employee record"
on public.employees for select
to authenticated
using (
  exists (
    select 1
    from public.profiles
    where profiles.id = employees.profile_id
      and profiles.supabase_user_id = auth.uid()
  )
);

drop policy if exists "Employees can update their own employee record" on public.employees;

create policy "Employees can update their own employee record"
on public.employees for update
to authenticated
using (
  exists (
    select 1
    from public.profiles
    where profiles.id = employees.profile_id
      and profiles.supabase_user_id = auth.uid()
  )
)
with check (profile_id = (
  select profiles.id
  from public.profiles
  where profiles.supabase_user_id = auth.uid()
));
