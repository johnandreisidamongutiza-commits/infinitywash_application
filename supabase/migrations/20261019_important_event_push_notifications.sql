-- Push notifications for important customer, payment, staff, and rider events.
-- Uses public.push_notify from 20261006_push_auto_notify.sql. That helper
-- requires the send-push-notification Edge Function and its Vault secrets.

-- ------------------------------------------------------------
-- Customer request decisions, payment due, and order milestones
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_important_order_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_order_number text;
  v_is_mobile_request boolean;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  SELECT p.supabase_user_id, o.order_number, (o.source = 'mobile_app')
    INTO v_user_id, v_order_number, v_is_mobile_request
    FROM public.orders o
    JOIN public.customers c ON c.id = o.customer_id
    JOIN public.profiles p ON p.id = c.profile_id
   WHERE o.id = NEW.id
   LIMIT 1;

  IF v_user_id IS NULL THEN
    RETURN NEW; -- Walk-in orders do not have an app account to notify.
  END IF;

  -- A customer request is accepted when staff moves it out of review into
  -- the normal processing / pickup flow.
  IF v_is_mobile_request
     AND OLD.status = 'pending_approval'
     AND NEW.status IN ('pending_pickup', 'processing') THEN
    IF lower(coalesce(NEW.payment_preference, '')) = 'gcash'
       AND coalesce(NEW.payment_status, 'pending') <> 'paid' THEN
      PERFORM public.push_notify(
        'Request accepted — payment due',
        'Your request ' || coalesce(v_order_number, '') ||
          ' was accepted. Please submit your GCash payment in the app.',
        'customer', ARRAY[v_user_id]
      );
    ELSE
      PERFORM public.push_notify(
        'Request accepted',
        'Your request ' || coalesce(v_order_number, '') ||
          ' was accepted. Open the app to see the next steps.',
        'customer', ARRAY[v_user_id]
      );
    END IF;
    RETURN NEW;
  END IF;

  CASE NEW.status
    WHEN 'ready' THEN
      PERFORM public.push_notify(
        'Order ready',
        'Order ' || coalesce(v_order_number, '') || ' is ready.',
        'customer', ARRAY[v_user_id]
      );
    WHEN 'out_for_delivery' THEN
      PERFORM public.push_notify(
        'Your order is on the way',
        'Order ' || coalesce(v_order_number, '') || ' is out for delivery.',
        'customer', ARRAY[v_user_id]
      );
    WHEN 'completed' THEN
      PERFORM public.push_notify(
        'Order completed',
        'Order ' || coalesce(v_order_number, '') || ' has been completed.',
        'customer', ARRAY[v_user_id]
      );
    WHEN 'rejected' THEN
      IF v_is_mobile_request AND OLD.status = 'pending_approval' THEN
        PERFORM public.push_notify(
          'Request declined',
          'Your service request was declined. Open the app for details.',
          'customer', ARRAY[v_user_id]
        );
      END IF;
    ELSE
      NULL; -- Avoid noisy pushes for routine intermediate transitions.
  END CASE;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_order_status ON public.orders;
CREATE TRIGGER trg_notify_order_status
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_important_order_event();

-- ------------------------------------------------------------
-- GCash payment verified / rejected -> notify the order's customer
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_customer_payment_result()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_order_number text;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status
     OR NEW.status NOT IN ('verified', 'rejected') THEN
    RETURN NEW;
  END IF;

  SELECT p.supabase_user_id, o.order_number
    INTO v_user_id, v_order_number
    FROM public.orders o
    JOIN public.customers c ON c.id = o.customer_id
    JOIN public.profiles p ON p.id = c.profile_id
   WHERE o.id = NEW.order_id
   LIMIT 1;

  IF v_user_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'verified' THEN
    PERFORM public.push_notify(
      'Payment verified',
      'Your GCash payment for order ' || coalesce(v_order_number, '') ||
        ' was verified.',
      'customer', ARRAY[v_user_id]
    );
  ELSE
    PERFORM public.push_notify(
      'Payment needs attention',
      'Your GCash payment for order ' || coalesce(v_order_number, '') ||
        ' was not verified. Please open the app and submit payment again.',
      'customer', ARRAY[v_user_id]
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_customer_payment_result ON public.payments;
CREATE TRIGGER trg_notify_customer_payment_result
  AFTER UPDATE OF status ON public.payments
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_customer_payment_result();

-- Staff need to know when a customer submits a receipt that requires review.
CREATE OR REPLACE FUNCTION public.notify_staff_payment_review()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'pending_review' AND NEW.source = 'mobile_app' THEN
    PERFORM public.push_notify(
      'GCash payment needs review',
      'A customer submitted a GCash receipt for verification.',
      'staff'
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_staff_payment_review
  ON public.gcash_receipt_submissions;
CREATE TRIGGER trg_notify_staff_payment_review
  AFTER INSERT ON public.gcash_receipt_submissions
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_staff_payment_review();

-- ------------------------------------------------------------
-- Rider jobs: new/reopened availability, assignment, cancellation
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_rider_job_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order_number text;
  v_rider_user_id uuid;
BEGIN
  SELECT order_number INTO v_order_number
    FROM public.orders
   WHERE id = NEW.order_id;

  IF TG_OP = 'INSERT' THEN
    IF NEW.status = 'pending' AND NEW.rider_id IS NULL THEN
      PERFORM public.push_notify(
        'New rider job available',
        'A new ' || coalesce(NEW.job_type, 'delivery') ||
          ' job is available. Open the app to view it.',
        'rider'
      );
    END IF;
    RETURN NEW;
  END IF;

  -- A job that was claimed, cancelled, or temporarily unavailable has become
  -- open again. Alert riders only on the transition, not on every edit.
  IF NEW.status = 'pending'
     AND NEW.rider_id IS NULL
     AND (OLD.status IS DISTINCT FROM NEW.status
          OR OLD.rider_id IS DISTINCT FROM NEW.rider_id) THEN
    PERFORM public.push_notify(
      'Rider job available again',
      'A ' || coalesce(NEW.job_type, 'delivery') ||
        ' job is available. Open the app to view it.',
      'rider'
    );
  END IF;

  -- Tell the currently assigned rider about cancellation or reassignment.
  IF OLD.rider_id IS NOT NULL
     AND (NEW.status = 'cancelled'
          OR (NEW.rider_id IS NOT NULL
              AND NEW.rider_id IS DISTINCT FROM OLD.rider_id)) THEN
    SELECT p.supabase_user_id INTO v_rider_user_id
      FROM public.employees e
      JOIN public.profiles p ON p.id = e.profile_id
     WHERE e.id = OLD.rider_id
     LIMIT 1;

    IF v_rider_user_id IS NOT NULL THEN
      PERFORM public.push_notify(
        CASE WHEN NEW.status = 'cancelled'
          THEN 'Rider job cancelled' ELSE 'Rider job reassigned' END,
        'Your ' || coalesce(OLD.job_type, 'delivery') || ' job for order ' ||
          coalesce(v_order_number, '') || ' has changed. Open the app for details.',
        'rider', ARRAY[v_rider_user_id]
      );
    END IF;
  END IF;

  -- If staff assigns a job directly, notify the new rider.
  IF NEW.rider_id IS NOT NULL
     AND NEW.rider_id IS DISTINCT FROM OLD.rider_id
     AND NEW.status = 'pending' THEN
    SELECT p.supabase_user_id INTO v_rider_user_id
      FROM public.employees e
      JOIN public.profiles p ON p.id = e.profile_id
     WHERE e.id = NEW.rider_id
     LIMIT 1;

    IF v_rider_user_id IS NOT NULL THEN
      PERFORM public.push_notify(
        'Rider job assigned',
        'A ' || coalesce(NEW.job_type, 'delivery') || ' job was assigned to you.',
        'rider', ARRAY[v_rider_user_id]
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_new_dispatch_job ON public.dispatch_jobs;
DROP TRIGGER IF EXISTS trg_notify_rider_job_change ON public.dispatch_jobs;
CREATE TRIGGER trg_notify_rider_job_change
  AFTER INSERT OR UPDATE OF status, rider_id ON public.dispatch_jobs
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_rider_job_change();

-- The existing staff alert for new mobile service requests remains in place.
