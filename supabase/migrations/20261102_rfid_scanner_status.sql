-- =====================================================
-- RFID Scanner Session & Status Control
-- =====================================================
-- Purpose: Controls whether the hardware RFID scanner (ESP32) is active.
--          Only allows scanning when the Loyalty Card Scanner page is open.
-- Date: 2026-11-02
-- =====================================================

-- 1. Create table to store the scanner status & heartbeat
CREATE TABLE IF NOT EXISTS public.rfid_scanner_status (
  id INT PRIMARY KEY DEFAULT 1,
  is_active BOOLEAN NOT NULL DEFAULT false,
  last_heartbeat TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed row id=1
INSERT INTO public.rfid_scanner_status (id, is_active, last_heartbeat, updated_at)
VALUES (1, false, now(), now())
ON CONFLICT (id) DO NOTHING;

-- 2. Enable RLS
ALTER TABLE public.rfid_scanner_status ENABLE ROW LEVEL SECURITY;

-- Allow anon and authenticated to SELECT
DROP POLICY IF EXISTS "rfid_scanner_status_select" ON public.rfid_scanner_status;
CREATE POLICY "rfid_scanner_status_select" ON public.rfid_scanner_status
  FOR SELECT TO anon, authenticated
  USING (true);

-- Allow authenticated and anon to UPDATE status & heartbeat
DROP POLICY IF EXISTS "rfid_scanner_status_update" ON public.rfid_scanner_status;
CREATE POLICY "rfid_scanner_status_update" ON public.rfid_scanner_status
  FOR UPDATE TO anon, authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "rfid_scanner_status_insert" ON public.rfid_scanner_status;
CREATE POLICY "rfid_scanner_status_insert" ON public.rfid_scanner_status
  FOR INSERT TO anon, authenticated
  WITH CHECK (true);

GRANT ALL ON public.rfid_scanner_status TO anon, authenticated;

-- 3. Create view vw_rfid_scanner_status with automatic heartbeat expiry (25s)
-- If the app is killed or loses connectivity, is_active automatically evaluates to false!
CREATE OR REPLACE VIEW public.vw_rfid_scanner_status AS
SELECT 
  id,
  (is_active = true AND (now() - last_heartbeat) < INTERVAL '25 seconds') AS is_active,
  last_heartbeat,
  updated_at
FROM public.rfid_scanner_status
WHERE id = 1;

GRANT SELECT ON public.vw_rfid_scanner_status TO anon, authenticated;

