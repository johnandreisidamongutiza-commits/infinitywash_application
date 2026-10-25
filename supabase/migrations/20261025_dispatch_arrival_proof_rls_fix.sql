-- Storage policies can run into the source tables' own RLS rules. These
-- narrowly-scoped SECURITY DEFINER checks verify the job/rider relationship
-- against the underlying rows while keeping the bucket private.
CREATE OR REPLACE FUNCTION public.can_upload_dispatch_proof(object_name text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.dispatch_jobs dj
    JOIN public.employees e
      ON e.id = dj.rider_id
     AND e.role = 'rider'
     AND e.status = 'active'
    JOIN public.profiles p
      ON p.id = e.profile_id
     AND p.supabase_user_id = auth.uid()
    WHERE dj.id::text = (storage.foldername(object_name))[1]
  );
$$;

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
    JOIN public.employees e
      ON e.id = dj.rider_id
     AND e.role = 'rider'
    JOIN public.profiles p
      ON p.id = e.profile_id
     AND p.supabase_user_id = auth.uid()
     AND p.role = 'rider'
    WHERE dj.id::text = (storage.foldername(object_name))[1]
  ) OR EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.supabase_user_id = auth.uid()
      AND p.role IN ('admin', 'superadmin', 'staff')
      AND EXISTS (
        SELECT 1
        FROM public.dispatch_jobs dj
        WHERE dj.id::text = (storage.foldername(object_name))[1]
      )
  );
$$;

REVOKE ALL ON FUNCTION public.can_upload_dispatch_proof(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_read_dispatch_proof(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_upload_dispatch_proof(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_read_dispatch_proof(text) TO authenticated;

DROP POLICY IF EXISTS "dispatch_proofs_rider_insert" ON storage.objects;
CREATE POLICY "dispatch_proofs_rider_insert"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'dispatch-proofs'
  AND public.can_upload_dispatch_proof(name)
);

DROP POLICY IF EXISTS "dispatch_proofs_authorized_read" ON storage.objects;
CREATE POLICY "dispatch_proofs_authorized_read"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'dispatch-proofs'
  AND public.can_read_dispatch_proof(name)
);

DROP POLICY IF EXISTS "dispatch_proofs_rider_delete" ON storage.objects;
CREATE POLICY "dispatch_proofs_rider_delete"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'dispatch-proofs'
  AND public.can_upload_dispatch_proof(name)
);
