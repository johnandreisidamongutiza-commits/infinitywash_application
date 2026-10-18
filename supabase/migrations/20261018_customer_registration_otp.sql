-- Pending customer registrations are private server-side OTP state.
CREATE TABLE IF NOT EXISTS public.pending_customer_registrations (
  email text PRIMARY KEY,
  registration_data jsonb NOT NULL,
  code_hash text NOT NULL,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz NOT NULL DEFAULT now(),
  send_count integer NOT NULL DEFAULT 1 CHECK (send_count BETWEEN 1 AND 3),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 5)
);
ALTER TABLE public.pending_customer_registrations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pending_customer_registrations FROM anon, authenticated;
GRANT ALL ON public.pending_customer_registrations TO service_role;
COMMENT ON TABLE public.pending_customer_registrations IS
  'Temporary customer signup details and OTP hashes. Service-role Edge Function only; OTPs expire after 15 minutes and records are removed after one hour.';
