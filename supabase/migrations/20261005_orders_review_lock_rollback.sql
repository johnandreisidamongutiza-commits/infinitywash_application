-- Rollback: remove the review lock columns and index.

drop index if exists public.orders_under_review_by_idx;

alter table public.orders
  drop column if exists under_review_at;

alter table public.orders
  drop column if exists under_review_by;
