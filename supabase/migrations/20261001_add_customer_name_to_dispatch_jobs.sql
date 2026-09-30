-- Add customer_name column to dispatch_jobs table
-- This allows riders to see customer names without joining tables

-- Add the column
ALTER TABLE dispatch_jobs 
ADD COLUMN customer_name VARCHAR(160) NULL;

-- Add index for searching by customer name (optional but helpful)
CREATE INDEX idx_dispatch_jobs_customer_name 
ON dispatch_jobs(customer_name) 
WHERE customer_name IS NOT NULL;

-- Backfill existing records from orders table
-- This updates any existing dispatch jobs to include customer names
UPDATE dispatch_jobs dj
SET customer_name = (
  SELECT 
    CASE 
      WHEN c.last_name IS NOT NULL AND c.last_name != '' 
      THEN TRIM(CONCAT(c.first_name, ' ', c.last_name))
      WHEN c.first_name IS NOT NULL AND c.first_name != ''
      THEN c.first_name
      ELSE 'Unknown Customer'
    END
  FROM orders o
  JOIN customers c ON c.id = o.customer_id
  WHERE o.id = dj.order_id
  LIMIT 1
)
WHERE customer_name IS NULL;

COMMENT ON COLUMN dispatch_jobs.customer_name IS 'Customer full name at time of job creation - denormalized for rider app performance';
