-- ============================================================
-- Fix staff "new order to review" push notification trigger
-- Date: 2026-11-07
--
-- Problem: The original trigger only fires on INSERT.
-- A walk-in order that is converted/updated to pending_approval
-- via an UPDATE would not notify staff.
--
-- Fix: Fire on AFTER INSERT OR UPDATE OF status so that:
--   - New mobile_app orders inserted with pending_approval ✓
--   - Existing orders whose status transitions TO pending_approval ✓
--   - Duplicate fires (old.status = pending_approval unchanged) blocked ✓
-- ============================================================

-- Replace the function with a version that handles both INSERT and UPDATE.
CREATE OR REPLACE FUNCTION public.notify_new_service_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only notify for mobile_app orders entering pending_approval.
  -- On INSERT, TG_OP = 'INSERT' and OLD is undefined (use IS DISTINCT FROM null check).
  -- On UPDATE, only fire when the status actually changed TO pending_approval.
  IF new.source = 'mobile_app'
     AND new.status = 'pending_approval'
     AND (
       TG_OP = 'INSERT'
       OR (TG_OP = 'UPDATE' AND old.status IS DISTINCT FROM 'pending_approval')
     )
  THEN
    PERFORM public.push_notify(
      'New service request 📋',
      'A customer submitted a new request. Open the app to review it.',
      'staff'
    );
  END IF;
  RETURN new;
END;
$$;

-- Drop the old INSERT-only trigger and replace with INSERT OR UPDATE.
DROP TRIGGER IF EXISTS trg_notify_new_service_request ON public.orders;

CREATE TRIGGER trg_notify_new_service_request
  AFTER INSERT OR UPDATE OF status ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_new_service_request();

-- ============================================================
-- Done. No Vault secret changes required.
-- ============================================================

