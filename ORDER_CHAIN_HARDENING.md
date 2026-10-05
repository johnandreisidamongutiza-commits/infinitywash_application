# Order → Pickup → Delivery Chain Hardening

Fixes for four failure modes in the order lifecycle chain: double-claimed rider
jobs, lost loyalty points on rider-completed deliveries, uncoordinated staff
order review, and bad data (fake coordinates, mixed `source` values, order
number collisions).

## Phase 1 — Rider job claiming (atomic)

**Files:** `lib/services/rider_service.dart`,
`lib/screens/rider/jobs/rider_job_details_screen.dart`

- `RiderService.startJob()` now claims jobs atomically: a single `UPDATE`
  guarded by `.or('rider_id.is.null,rider_id.eq.<me>')` plus
  `.neq('status', ...)` filters. If another rider claimed first, the update
  matches 0 rows and `JobClaimedException` is thrown.
- Claims record WHO took the job (`rider_id` = `employees.id`, resolved via
  `getCurrentRiderEmployeeId()`); `assigned_at` is stamped on first claim only.
- Added `isJobStillAvailable()`; the job details screen verifies on open, shows
  a red "taken by another rider" banner instead of the Start button, and an
  orange warning when a job has no map pin.
- Deleted dead code: `rider_service_backup.dart`, `dispatch_service.dart`.

## Phase 2 — Loyalty points on every completion path

**Files:** `lib/services/order_service.dart`, `lib/services/supabase_service.dart`

- New `OrderService.completeOrder(orderId)`: single idempotent completion path
  (status update → `completed_at` → loyalty award).
- `updateOrderStatus('completed')` delegates to it; rider deliveries go
  `completeDispatchJobAction` → `completeOrder` for `delivery_done`. Points can
  no longer be lost on rider-completed deliveries or double-awarded on retries
  (award only runs on the actual transition into `completed`).

## Phase 3 — Staff review flow

**Files:** `lib/screens/staff/home/service_requests_screen.dart`,
`lib/screens/staff/orders/review_request_screen.dart`,
`lib/services/service_request_service.dart`

- Accept/Decline buttons wired on the service-requests screen (Accept asks for
  estimated loads 1–5; Decline records a reason).
- Review lock (`orders.under_review_by` / `under_review_at`): first staff
  member to open a request claims it for 30 minutes; others see
  "Being reviewed by X" with Decline/Accept disabled. Lock is released on
  dispose/decision, never for someone else's lock.
- Requests pending > 24h are auto-rejected (`expired_no_response`) on staff
  list refresh. All review timestamps written in UTC.

## Phase 4 — Data correctness

**Files:** `lib/services/order_service.dart`,
`lib/services/service_request_service.dart`, `lib/services/supabase_service.dart`,
`lib/models/order.dart`

- Removed all fake fallback coordinates (14.2811/121.4159); pickup/delivery
  job lat/lng are now nullable and honest.
- `orders.source` unified to `'walk_in' | 'mobile_app'`; legacy `'online'`
  still parses (mapped to `mobile_app`) but is never written.
- `createOrder` retries on `orders_order_number_key` collisions (bumps the
  trailing sequence, up to 5 attempts) instead of failing the order.

## Migration prerequisite

Apply before using the review-lock features (the app degrades gracefully
without it — review proceeds unlocked):

```
supabase/migrations/20261005_orders_review_lock.sql          (apply)
supabase/migrations/20261005_orders_review_lock_rollback.sql (undo)
```

Adds `orders.under_review_by uuid`, `orders.under_review_at timestamptz`,
index `orders_under_review_by_idx`.

## Manual E2E checklist

1. **Rider claim race** — two rider devices open the same job; both tap Start.
   Expected: one succeeds; the other sees "already taken by another rider" and
   the job list refreshes to show the job claimed by the other rider.
2. **No-pin job** — create a dispatch job without coordinates. Expected: job
   opens with the orange "No map pin" banner; Start still works.
3. **Loyalty on rider delivery** — complete a delivery as a rider for an order
   whose customer has a linked loyalty card. Expected: card gains
   `loads_count` points exactly once, even if the delivery confirm is tapped
   twice or staff later re-completes the order.
4. **Loyalty on staff completion** — staff sets an order to `completed`.
   Expected: same single award (shared path via `completeOrder`).
5. **Review lock** — two staff devices open the same pending request.
   Expected: the second shows "Being reviewed by <name>" and disabled
   Decline/Accept. Closing the screen frees it; waiting 30+ min also frees it.
6. **24h auto-reject** — leave a `mobile_app` request pending past
   `expires_at`, refresh the staff list. Expected: status `rejected`,
   reason `expired_no_response`.
7. **Order number collision** — create two orders simultaneously (two
   devices). Expected: both succeed with distinct `ORD-YYMMDD-NNN` numbers.
8. **No fake coordinates** — create a walk-in order without dropping a pin.
   Expected: dispatch job rows have `NULL` lat/lng, not 14.2811/121.4159.

## Automated tests

```
flutter test test/order_chain_guards_test.dart   # new chain-guard suite (20 tests)
flutter test                                      # full suite (65 passing)
dart analyze                                      # 0 errors
```

`test/order_chain_guards_test.dart` covers the claim truth table (unclaimed /
self-claimed / foreign-claimed / finished jobs), claim payload (UTC stamps,
`assigned_at` only on first claim), completeOrder idempotency decisions,
loyalty loads→points mapping, review-lock validity (fresh/stale/unparseable/
empty), and `source` channel parsing including the legacy `'online'` value.
