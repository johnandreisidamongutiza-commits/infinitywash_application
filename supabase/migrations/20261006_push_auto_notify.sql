-- ============================================================
-- Push auto-notify: FCM pushes on order/job/request events
-- Date: 2026-10-06
--
-- Calls the send-push-notification Edge Function asynchronously
-- (pg_net) whenever:
--   1. an order's status changes            -> push to the customer
--   2. a dispatch job is created            -> push to all riders
--   3. a mobile_app order enters pending    -> push to all staff
--
-- Credentials: the Edge Function URL and the service_role key are
-- read from Supabase Vault (NOT hardcoded). Setup:
--
--   select vault.create_secret(
--     'https://<PROJECT-REF>.supabase.co/functions/v1/send-push-notification',
--     'push_function_url'
--   );
--   select vault.create_secret(
--     '<service_role key>',   -- Project Settings -> API -> service_role
--     'push_service_role_key'
--   );
--
-- Until both secrets exist the triggers are silent no-ops.
-- ============================================================

create extension if not exists pg_net;

-- ------------------------------------------------------------
-- Helper: fire-and-forget POST to the Edge Function.
-- Never raises: a push failure must never fail the DB write.
-- ------------------------------------------------------------
create or replace function public.push_notify(
  p_title    text,
  p_body     text,
  p_audience text,                      -- 'all' | 'customer' | 'staff' | 'rider'
  p_user_ids uuid[] default null        -- explicit targets override audience
) returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
declare
  v_url  text;
  v_key  text;
  v_body jsonb;
begin
  if p_title is null or p_body is null then
    return;
  end if;

  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'push_function_url';
  select decrypted_secret into v_key
    from vault.decrypted_secrets where name = 'push_service_role_key';

  -- Not configured yet: silently skip (feature degrades gracefully).
  if v_url is null or v_key is null or v_url = '' or v_key = '' then
    return;
  end if;

  v_body := jsonb_build_object(
    'title',    p_title,
    'body',     p_body,
    'audience', coalesce(p_audience, 'all')
  );
  if p_user_ids is not null and array_length(p_user_ids, 1) > 0 then
    v_body := v_body || jsonb_build_object('user_ids', p_user_ids);
  end if;

  perform net.http_post(
    url     := v_url,
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_key
    ),
    body    := v_body
  );
exception when others then
  -- Swallow everything (network down, pg_net error, ...). The
  -- pg_net request may still be in flight; this only guards the
  -- trigger path. Push failures must never block business flow.
  return;
end $$;

-- ------------------------------------------------------------
-- 1) ORDER STATUS CHANGE -> notify the order's customer
--    (only on actual transitions, only for statuses worth a push)
-- ------------------------------------------------------------
create or replace function public.notify_order_status() returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid;
  v_num  text;
begin
  if new.status is null or new.status = old.status then
    return new;
  end if;

  select p.supabase_user_id, o.order_number
    into v_user, v_num
    from public.orders o
    join public.customers c on c.id = o.customer_id
    join public.profiles  p on p.id = c.profile_id
   where o.id = new.id
   limit 1;

  if v_user is null then
    return new;                         -- walk-in order without an app account
  end if;

  case new.status
    when 'ready' then
      perform public.push_notify(
        'Order ready! 🧺',
        'Order ' || coalesce(v_num, '') || ' is ready for pickup.',
        'customer', array[v_user]);
    when 'out_for_delivery' then
      perform public.push_notify(
        'On the way 🛵',
        'Order ' || coalesce(v_num, '') || ' is out for delivery.',
        'customer', array[v_user]);
    when 'completed' then
      perform public.push_notify(
        'Completed ✅',
        'Order ' || coalesce(v_num, '') || ' is complete. Thank you!',
        'customer', array[v_user]);
    when 'rejected' then
      perform public.push_notify(
        'Request declined',
        'Your service request was reviewed and declined. Please contact the shop for details.',
        'customer', array[v_user]);
    else
      null;                             -- processing, cancelled, etc.: no push
  end case;

  return new;
end $$;

drop trigger if exists trg_notify_order_status on public.orders;
create trigger trg_notify_order_status
  after update of status on public.orders
  for each row
  execute function public.notify_order_status();

-- ------------------------------------------------------------
-- 2) NEW DISPATCH JOB -> notify all active riders
--    (open-claim model: every rider sees every open job)
-- ------------------------------------------------------------
create or replace function public.notify_new_dispatch_job() returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job_type text;
begin
  v_job_type := coalesce(new.job_type, 'job');
  perform public.push_notify(
    'New job available! 📦',
    'A new ' || v_job_type || ' job needs a rider. Open the app to claim it.',
    'rider');
  return new;
end $$;

drop trigger if exists trg_notify_new_dispatch_job on public.dispatch_jobs;
create trigger trg_notify_new_dispatch_job
  after insert on public.dispatch_jobs
  for each row
  execute function public.notify_new_dispatch_job();

-- ------------------------------------------------------------
-- 3) NEW MOBILE SERVICE REQUEST -> notify all staff
-- ------------------------------------------------------------
create or replace function public.notify_new_service_request() returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.source = 'mobile_app' and new.status = 'pending_approval' then
    perform public.push_notify(
      'New service request 📋',
      'A customer submitted a new request. Open the app to review it.',
      'staff');
  end if;
  return new;
end $$;

drop trigger if exists trg_notify_new_service_request on public.orders;
create trigger trg_notify_new_service_request
  after insert on public.orders
  for each row
  execute function public.notify_new_service_request();

-- ============================================================
-- Done. Remember to create the two Vault secrets (see header).
-- ============================================================
