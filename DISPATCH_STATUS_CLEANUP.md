# Dispatch Job Status Cleanup

## Problem
The database constraint on `dispatch_jobs.status` was outdated and causing errors:
- ❌ Missing: `pickup_done`, `delivery_done` (actually used in code)
- ❌ Had: `assigned` (not used - no rider assignment)
- ❌ Had: `done`, `completed` (redundant with pickup_done/delivery_done)

## Solution - Simplified Status Flow

### Final Status Values

| Status | When | Purpose |
|--------|------|---------|
| `pending` | Job created | Waiting for rider to start |
| `in_progress` | Rider starts job | Rider is en route to location |
| `pickup_done` | Pickup completed | Laundry picked up from customer |
| `delivery_done` | Delivery completed | Laundry delivered to customer |
| `cancelled` | Job cancelled | Job will not be completed |

### Removed Status Values

| Status | Why Removed |
|--------|-------------|
| `assigned` | Not used - system doesn't assign riders (all jobs unassigned with rider_id=NULL) |
| `done` | Too generic - doesn't distinguish pickup vs delivery |
| `completed` | Never actually used in code |

## Status Flow

### Pickup Job
```
pending → in_progress → pickup_done
```

### Delivery Job
```
pending → in_progress → delivery_done
```

### Either Job
```
pending/in_progress → cancelled
```

## Changes Made

### 1. Database Migration ✅
**File:** `supabase/migrations/20261001_fix_dispatch_jobs_status_constraint.sql`

- Dropped old constraint
- Added new constraint with: pending, in_progress, pickup_done, delivery_done, cancelled
- Migrated any existing data:
  - `assigned` → `pending`
  - `done` → `pickup_done` or `delivery_done` (based on job_type)
  - `completed` → `pickup_done` or `delivery_done` (based on job_type)

### 2. Code Updates ✅

**lib/models/dispatch_job.dart**
- `isCompleted`: Now checks for `pickup_done` OR `delivery_done`
- `isPending`: Now only checks for `pending` (removed `assigned`)

**lib/state/dispatch_job_provider.dart**
- `pendingJobs`: Removed `assigned` check
- Active job selection: Removed `assigned` check

**lib/services/rider_service.dart**
- `getPendingJobs()`: Query changed from `eq('status', 'assigned')` to `eq('status', 'pending')`
- `getCompletedJobs()`: Now returns both `pickup_done` and `delivery_done` jobs
- `getRiderStats()`: Updated to count both completion statuses

**lib/screens/rider/jobs/rider_job_details_screen.dart**
- Start button: Removed `assigned` condition

## Status Triggers

### pickup_done triggers:
- `orders.status` → `'processing'` (via syncOrderStatus)
- Laundry enters processing workflow

### delivery_done triggers:
- `orders.status` → `'completed'` (via syncOrderStatus)
- Order fully complete

## Benefits

1. **Clearer semantics** - Status names match actual business events
2. **Better tracking** - Can distinguish pickup completion from delivery completion
3. **Simpler logic** - Removed unused `assigned` status
4. **Accurate reporting** - Can track pickup vs delivery completions separately
5. **Matches actual workflow** - No rider assignment, jobs go straight from pending to in_progress

## Testing

Run the migration:
```bash
cd supabase
supabase db push
```

Then test:
1. ✅ Create pickup job - should have status 'pending'
2. ✅ Rider starts job - should change to 'in_progress'
3. ✅ Rider completes pickup - should change to 'pickup_done' (no more constraint error!)
4. ✅ Staff marks order ready - delivery job created with 'pending'
5. ✅ Rider starts delivery - should change to 'in_progress'
6. ✅ Rider completes delivery - should change to 'delivery_done'

## Database Impact

- Constraint updated
- Any existing jobs with old statuses automatically migrated
- No data loss
- Backwards compatible (old status values converted to new ones)
