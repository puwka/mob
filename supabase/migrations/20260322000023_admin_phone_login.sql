-- ============================================================
-- Admin login by phone: rename admin_users.email → phone
-- (safe if 000022 already applied with email column)
-- ============================================================

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'admin_users'
      AND column_name = 'email'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'admin_users'
      AND column_name = 'phone'
  ) THEN
    ALTER TABLE public.admin_users RENAME COLUMN email TO phone;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.admin_me()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.admin_users;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_row FROM public.admin_users WHERE id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object(
    'id', v_row.id,
    'phone', v_row.phone,
    'role', v_row.role,
    'created_at', v_row.created_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_me() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_me() TO authenticated;

COMMENT ON COLUMN public.admin_users.phone IS 'E.164 phone (+7…); Auth identity is {digits}@phone.local';
