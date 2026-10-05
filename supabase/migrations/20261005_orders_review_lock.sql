-- Review lock for online service requests.
-- Lets staff claim a request while reviewing it so two staff members
-- cannot approve/decline the same request at the same time.

alter table public.orders
  add column if not exists under_review_by uuid null;

-- Clear stale locks automatically: if a request stays untouched for 30
-- minutes after being claimed, the lock is treated as abandoned by the app
-- (under_review_at + 30 min < now).
create index if not exists orders_under_review_by_idx on public.orders (under_review_by);

alter table public.orders
  add column if not exists under_review_at timestamptz null;

-- reviewed_by references employees(id); under_review_by holds the same kind
-- of value but no FK so staff without an employee row can still be tracked
-- (it stores the auth user id in that case).
