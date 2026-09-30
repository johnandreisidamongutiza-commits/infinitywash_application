-- Fix dispatch_jobs status constraint
-- Remove: assigned, done, completed (not used or redundant)
-- Add: pickup_done, delivery_done (actually used in code)
-- Keep: pending, in_progress, cancelled

-- Drop the old constraint
ALTER TABLE dispatch_jobs DROP CONSTRAINT IF EXISTS dispatch_jobs_status_check;

-- Add the new constraint with correct status values
ALTER TABLE dispatch_jobs ADD CONSTRAINT dispatch_jobs_status_check 
  CHECK (status IN ('pending', 'in_progress', 'pickup_done', 'delivery_done', 'cancelled'));

-- Update any existing 'assigned' status to 'pending' (if any exist)
UPDATE dispatch_jobs SET status = 'pending' WHERE status = 'assigned';

-- Update any existing 'done' status based on job_type (if any exist)
UPDATE dispatch_jobs 
SET status = CASE 
  WHEN job_type = 'pickup' THEN 'pickup_done'
  WHEN job_type = 'delivery' THEN 'delivery_done'
  ELSE 'pickup_done' -- fallback
END 
WHERE status = 'done';

-- Update any existing 'completed' status (if any exist)
UPDATE dispatch_jobs 
SET status = CASE 
  WHEN job_type = 'pickup' THEN 'pickup_done'
  WHEN job_type = 'delivery' THEN 'delivery_done'
  ELSE 'delivery_done' -- fallback
END 
WHERE status = 'completed';

-- Add comment explaining the status flow
COMMENT ON COLUMN dispatch_jobs.status IS 
'Job status: pending (created, waiting to start) → in_progress (rider en route) → pickup_done (pickup completed) OR delivery_done (delivery completed). Can be cancelled at any time.';
