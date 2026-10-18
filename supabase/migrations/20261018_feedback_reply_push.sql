-- Notify app customers when an administrator replies to their feedback.
-- The shared push helper is configured through Supabase Vault by
-- 20261006_push_auto_notify.sql; if the push service is not configured,
-- saving the feedback reply still succeeds.

create or replace function public.notify_feedback_admin_reply()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
begin
  if new.admin_reply is null
     or btrim(new.admin_reply) = ''
     or new.admin_reply is not distinct from old.admin_reply then
    return new;
  end if;

  select p.supabase_user_id
    into v_user_id
    from public.customers c
    join public.profiles p on p.id = c.profile_id
   where c.id = new.customer_id
   limit 1;

  if v_user_id is not null then
    perform public.push_notify(
      'Reply to your feedback',
      'InfinityWash replied to your feedback. Open your order details to read it.',
      'customer',
      array[v_user_id]
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_feedback_admin_reply on public.feedback;
create trigger trg_notify_feedback_admin_reply
  after update of admin_reply on public.feedback
  for each row
  execute function public.notify_feedback_admin_reply();
