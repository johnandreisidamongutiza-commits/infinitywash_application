-- =====================================================
-- Trigger: Sync gcash_receipt_submissions status → payments + orders
-- =====================================================
-- Purpose: When the admin website updates gcash_receipt_submissions.status
--          (verified / rejected), automatically sync:
--            • payments.status  (pending → verified / rejected)
--            • orders.payment_status (paid → unpaid on rejection)
--
-- Idempotent: safe to run more than once.
-- =====================================================

-- Drop existing trigger + function if re-running
DROP TRIGGER IF EXISTS trg_gcash_submission_status_sync ON public.gcash_receipt_submissions;
DROP FUNCTION IF EXISTS public.fn_gcash_submission_status_sync();

-- -----------------------------------------------------
-- Function: sync status changes to payments & orders
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_gcash_submission_status_sync()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_order_id uuid;
BEGIN
  -- Only fire when the status column actually changed
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  -- We need the payment_id to update payments
  IF NEW.payment_id IS NULL THEN
    RAISE NOTICE '⚠️ gcash_receipt_submissions id=% has no payment_id — skipping sync.', NEW.id;
    RETURN NEW;
  END IF;

  -- ─── VERIFIED ────────────────────────────────────────
  IF NEW.status = 'verified' THEN

    -- Update payments row: pending → verified
    UPDATE public.payments
    SET status     = 'verified',
        updated_at = now()
    WHERE id = NEW.payment_id;

    -- Also stamp verified_at if the admin didn't set it
    IF NEW.verified_at IS NULL THEN
      NEW.verified_at := now();
    END IF;

    RAISE NOTICE '✅ Payment % marked verified (submission %).', NEW.payment_id, NEW.id;

  -- ─── REJECTED ────────────────────────────────────────
  ELSIF NEW.status = 'rejected' THEN

    -- Update payments row: pending → rejected
    UPDATE public.payments
    SET status     = 'rejected',
        updated_at = now()
    WHERE id = NEW.payment_id;

    -- Revert the order back to unpaid so staff knows to collect again
    -- Look up the order_id from the submission or from the payment
    v_order_id := NEW.order_id;

    IF v_order_id IS NULL THEN
      SELECT order_id INTO v_order_id
      FROM public.payments
      WHERE id = NEW.payment_id;
    END IF;

    IF v_order_id IS NOT NULL THEN
      UPDATE public.orders
      SET payment_status = 'unpaid',
          updated_at     = now()
      WHERE id = v_order_id
        AND payment_method = 'gcash';

      RAISE NOTICE '⚠️ Order % reverted to unpaid (rejected submission %).', v_order_id, NEW.id;
    END IF;

    RAISE NOTICE '❌ Payment % marked rejected (submission %).', NEW.payment_id, NEW.id;

  -- ─── PENDING_REVIEW (re-opened / re-submitted) ──────
  ELSIF NEW.status = 'pending_review' AND OLD.status IN ('verified', 'rejected') THEN

    UPDATE public.payments
    SET status     = 'pending',
        updated_at = now()
    WHERE id = NEW.payment_id;

    -- Re-mark order as paid (benefit of the doubt while under review)
    v_order_id := NEW.order_id;

    IF v_order_id IS NULL THEN
      SELECT order_id INTO v_order_id
      FROM public.payments
      WHERE id = NEW.payment_id;
    END IF;

    IF v_order_id IS NOT NULL THEN
      UPDATE public.orders
      SET payment_status = 'paid',
          updated_at     = now()
      WHERE id = v_order_id
        AND payment_method = 'gcash';
    END IF;

    RAISE NOTICE '🔄 Payment % reset to pending (submission % re-opened).', NEW.payment_id, NEW.id;
  END IF;

  -- Always stamp updated_at on the submission itself
  NEW.updated_at := now();

  RETURN NEW;
END;
$$;

-- -----------------------------------------------------
-- Trigger: fires BEFORE UPDATE so we can modify NEW
-- -----------------------------------------------------
CREATE TRIGGER trg_gcash_submission_status_sync
  BEFORE UPDATE ON public.gcash_receipt_submissions
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_gcash_submission_status_sync();

DO $$
BEGIN
  RAISE NOTICE '✅ GCash submission ↔ payment status sync trigger installed.';
END $$;
