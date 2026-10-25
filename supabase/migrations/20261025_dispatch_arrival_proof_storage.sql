-- Keep rider arrival photos in a private bucket. proof_url stores the
-- bucket/object path so authorized users can request a signed URL.
INSERT INTO storage.buckets (id, name, public)
VALUES ('dispatch-proofs', 'dispatch-proofs', false)
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS "dispatch_proofs_rider_insert" ON storage.objects;
CREATE POLICY "dispatch_proofs_rider_insert"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'dispatch-proofs'
  AND EXISTS (
    SELECT 1
    FROM public.dispatch_jobs dj
    JOIN public.employees e ON e.id = dj.rider_id
    JOIN public.profiles p ON p.id = e.profile_id
    WHERE dj.id::text = (storage.foldername(name))[1]
      AND p.supabase_user_id = auth.uid()
      AND p.role = 'rider'
  )
);

DROP POLICY IF EXISTS "dispatch_proofs_authorized_read" ON storage.objects;
CREATE POLICY "dispatch_proofs_authorized_read"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'dispatch-proofs'
  AND EXISTS (
    SELECT 1
    FROM public.dispatch_jobs dj
    LEFT JOIN public.employees e ON e.id = dj.rider_id
    LEFT JOIN public.profiles rider_profile ON rider_profile.id = e.profile_id
    WHERE dj.id::text = (storage.foldername(name))[1]
      AND (
        rider_profile.supabase_user_id = auth.uid()
        OR EXISTS (
          SELECT 1
          FROM public.profiles viewer_profile
          WHERE viewer_profile.supabase_user_id = auth.uid()
            AND viewer_profile.role IN ('admin', 'superadmin', 'staff')
        )
      )
  )
);

DROP POLICY IF EXISTS "dispatch_proofs_rider_delete" ON storage.objects;
CREATE POLICY "dispatch_proofs_rider_delete"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'dispatch-proofs'
  AND EXISTS (
    SELECT 1
    FROM public.dispatch_jobs dj
    JOIN public.employees e ON e.id = dj.rider_id
    JOIN public.profiles p ON p.id = e.profile_id
    WHERE dj.id::text = (storage.foldername(name))[1]
      AND p.supabase_user_id = auth.uid()
      AND p.role = 'rider'
  )
);

COMMENT ON COLUMN public.dispatch_jobs.proof_url IS
  'Private storage object path in dispatch-proofs for rider arrival evidence.';
