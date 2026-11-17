-- Rollback: Remove is_phone_taken RPC function
DROP FUNCTION IF EXISTS public.is_phone_taken(TEXT, UUID);

