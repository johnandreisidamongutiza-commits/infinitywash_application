-- ============================================================
-- Rollback: remove push auto-notify triggers and functions.
-- (Keeps Vault secrets; delete those manually if desired.)
-- ============================================================

drop trigger if exists trg_notify_new_service_request on public.orders;
drop trigger if exists trg_notify_new_dispatch_job on public.dispatch_jobs;
drop trigger if exists trg_notify_order_status on public.orders;

drop function if exists public.notify_new_service_request();
drop function if exists public.notify_new_dispatch_job();
drop function if exists public.notify_order_status();
drop function if exists public.push_notify(text, text, text, uuid[]);

-- Leave pg_net installed: other features may depend on it.
-- To remove it as well (only if nothing else uses it):
--   drop extension if exists pg_net;
