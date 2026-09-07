-- ============================================================
-- User presence: last_seen_at + touch_presence RPC
-- ============================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS profiles_last_seen_at_idx
  ON public.profiles (last_seen_at DESC NULLS LAST);

COMMENT ON COLUMN public.profiles.last_seen_at IS
  'Last app heartbeat; online if within ~3 minutes';

CREATE OR REPLACE FUNCTION public.touch_presence()
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_at TIMESTAMPTZ := NOW();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  UPDATE public.profiles
  SET last_seen_at = v_at
  WHERE id = v_uid;

  RETURN v_at;
END;
$$;

REVOKE ALL ON FUNCTION public.touch_presence() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.touch_presence() TO authenticated;
