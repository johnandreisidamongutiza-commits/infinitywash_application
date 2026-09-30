# Dispatch Job Creation Fix

## Problem
Dispatch jobs were not being created when staff approved service requests, even though:
- Orders had `pickup_requested = true`
- The migration was applied to fix the status constraint
- The code was correctly using `status: 'pending'`

## Root Cause
The `_createDispatchJobsForApprovedOrder` method in `service_request_service.dart` was using an **INNER JOIN** on the customers table:

```dart
customers!inner(first_name, last_name, phone, address, landmark)
```

This caused the query to:
- **Fail silently** when `customer_id` was NULL (service requests without customers)
- Return **no rows** instead of the order data
- Throw an exception on `.single()` which was caught and suppressed

## Solution
Changed the query to use a **LEFT JOIN** (implicit in Supabase when you don't use `!inner`):

```dart
customers(first_name, last_name, phone, address, landmark)
```

This allows the query to work whether or not a customer record exists.

## Additional Improvements
1. **Better error logging** - Added detailed PostgrestException logging to catch similar issues
2. **Landmark handling** - Fixed to check both order-level and customer-level landmarks
3. **Null-safe customer data** - Already handled properly with `?` operators

## Changes Made

### File: `lib/services/service_request_service.dart`

1. **Line ~561**: Changed `customers!inner(...)` to `customers(...)`
2. **Line ~586**: Added proper landmark fallback logic
3. **Line ~648**: Enhanced error logging with PostgrestException details

## Testing
After this fix:
1. Orders with `pickup_requested = true` will create dispatch jobs
2. Works even when `customer_id` is NULL
3. Dispatch jobs will have `status = 'pending'` and `rider_id = NULL`
4. All riders will see these jobs in their app

## Next Steps
1. **Restart your Flutter app** to load the updated code
2. **Approve a new service request** with pickup requested
3. **Check the dispatch_jobs table** - you should now see entries
4. **Verify riders can see the jobs** in their app
