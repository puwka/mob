-- ============================================================
-- Assign admin panel roles (moderator / admin / super_admin)
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_get_panel_role(p_user_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
BEGIN
  PERFORM public.require_admin('admin');

  SELECT role INTO v_role
  FROM public.admin_users
  WHERE id = p_user_id;

  RETURN v_role;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_panel_role(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_panel_role(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_panel_role(
  p_user_id UUID,
  p_role TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_actor_role TEXT;
  v_target_role TEXT;
  v_new_role TEXT := NULLIF(lower(btrim(COALESCE(p_role, ''))), '');
  v_phone TEXT;
  v_old public.admin_users;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT role INTO v_actor_role
  FROM public.admin_users
  WHERE id = v_actor;

  IF v_actor_role IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_USER' USING ERRCODE = 'P0001';
  END IF;

  IF p_user_id = v_actor THEN
    RAISE EXCEPTION 'CANNOT_CHANGE_SELF' USING ERRCODE = 'P0001';
  END IF;

  IF v_new_role IS NOT NULL
     AND v_new_role NOT IN ('super_admin', 'admin', 'moderator') THEN
    RAISE EXCEPTION 'INVALID_ADMIN_ROLE' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_old
  FROM public.admin_users
  WHERE id = p_user_id;

  v_target_role := v_old.role;

  -- Permissions:
  -- super_admin: anything
  -- admin: can assign/remove moderator only
  IF v_actor_role = 'admin' THEN
    IF v_target_role IN ('super_admin', 'admin') THEN
      RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
    END IF;
    IF v_new_role IS NOT NULL AND v_new_role <> 'moderator' THEN
      RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
    END IF;
  ELSIF v_actor_role = 'moderator' THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  ELSIF v_actor_role <> 'super_admin' THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF v_new_role IS NULL THEN
    DELETE FROM public.admin_users WHERE id = p_user_id;
    PERFORM public.write_admin_audit(
      v_actor,
      'remove_panel_role',
      'admin_user',
      p_user_id::TEXT,
      CASE WHEN v_old.id IS NULL THEN NULL ELSE to_jsonb(v_old) END,
      NULL
    );
    RETURN NULL;
  END IF;

  SELECT phone INTO v_phone
  FROM public.profiles
  WHERE id = p_user_id;

  IF v_phone IS NULL OR btrim(v_phone) = '' THEN
    RAISE EXCEPTION 'PHONE_REQUIRED' USING ERRCODE = 'P0001';
  END IF;

  -- Normalize to +7… when possible
  v_phone := btrim(v_phone);
  IF left(v_phone, 1) <> '+' AND left(v_phone, 1) ~ '[0-9]' THEN
    v_phone := '+' || regexp_replace(v_phone, '\D', '', 'g');
  END IF;

  BEGIN
    INSERT INTO public.admin_users (id, phone, role)
    VALUES (p_user_id, v_phone, v_new_role)
    ON CONFLICT (id) DO UPDATE
      SET phone = EXCLUDED.phone,
          role = EXCLUDED.role
    RETURNING role INTO v_target_role;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'PHONE_TAKEN' USING ERRCODE = 'P0001';
  END;

  PERFORM public.write_admin_audit(
    v_actor,
    'set_panel_role',
    'admin_user',
    p_user_id::TEXT,
    CASE WHEN v_old.id IS NULL THEN NULL ELSE to_jsonb(v_old) END,
    jsonb_build_object('role', v_target_role, 'phone', v_phone)
  );

  RETURN v_target_role;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_panel_role(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_panel_role(UUID, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
