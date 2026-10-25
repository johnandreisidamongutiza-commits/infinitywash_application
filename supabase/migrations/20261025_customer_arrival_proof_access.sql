-- Allow customers to view only the arrival proofs attached to their own order.
CREATE OR REPLACE FUNCTION public.can_read_dispatch_proof(object_name text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.dispatch_jobs dj
    WHERE dj.id::text = (storage.foldername(object_name))[1]
      AND (
        EXISTS (
          SELECT 1
          FROM public.employees e
          JOIN public.profiles rider_profile ON rider_profile.id = e.profile_id
          WHERE e.id = dj.rider_id
            AND e.role = 'rider'
            AND rider_profile.supabase_user_id = auth.uid()
            AND rider_profile.role = 'rider'
        )
        OR EXISTS (
          SELECT 1
          FROM public.profiles viewer_profile
          WHERE viewer_profile.supabase_user_id = auth.uid()
            AND viewer_profile.role IN ('admin', 'superadmin', 'staff')
        )
        OR EXISTS (
          SELECT 1
          FROM public.orders o
          JOIN public.customers c ON c.id = o.customer_id
          JOIN public.profiles customer_profile ON customer_profile.id = c.profile_id
          WHERE o.id = dj.order_id
            AND customer_profile.supabase_user_id = auth.uid()
            AND customer_profile.role = 'customer'
        )
      )
  );
$$;

REVOKE ALL ON FUNCTION public.can_read_dispatch_proof(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_read_dispatch_proof(text) TO authenticated;

DROP POLICY IF EXISTS "dispatch_proofs_authorized_read" ON storage.objects;
CREATE POLICY "dispatch_proofs_authorized_read"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'dispatch-proofs'
  AND public.can_read_dispatch_proof(name)
);

CREATE OR REPLACE FUNCTION public.get_customer_arrival_proofs(p_order_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'job_type', dj.job_type,
        'proof_path', dj.proof_url,
        'created_at', dj.updated_at
      )
      ORDER BY dj.updated_at DESC
    ),
    '[]'::jsonb
  )
  FROM public.dispatch_jobs dj
  JOIN public.orders o ON o.id = dj.order_id
  JOIN public.customers c ON c.id = o.customer_id
  JOIN public.profiles p ON p.id = c.profile_id
  WHERE o.id = p_order_id
    AND p.supabase_user_id = auth.uid()
    AND p.role = 'customer'
    AND dj.proof_url LIKE 'dispatch-proofs/%';
$$;

REVOKE ALL ON FUNCTION public.get_customer_arrival_proofs(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_customer_arrival_proofs(uuid) TO authenticated;
