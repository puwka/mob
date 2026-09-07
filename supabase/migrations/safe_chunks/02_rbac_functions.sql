-- ========== BLOCK E: RBAC helpers (functions only — light locks) ==========
-- Paste entire file → Run once.

CREATE OR REPLACE FUNCTION public.admin_has_perm(p_perm TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
BEGIN
  SELECT role INTO v_role FROM public.admin_users WHERE id = auth.uid();
  IF v_role IS NULL THEN
    RETURN FALSE;
  END IF;

  IF v_role = 'super_admin' THEN
    RETURN TRUE;
  END IF;

  IF v_role = 'admin' THEN
    RETURN p_perm = ANY (ARRAY[
      'dashboard', 'users', 'organizers', 'events', 'clans', 'ranking',
      'market', 'moderation', 'dialogs', 'achievements', 'dictionaries',
      'economy_view', 'attendance', 'settings_view', 'notifications',
      'logs', 'search'
    ]);
  END IF;

  IF v_role = 'moderator' THEN
    RETURN p_perm = ANY (ARRAY[
      'dashboard', 'market', 'moderation', 'dialogs', 'logs', 'search'
    ]);
  END IF;

  RETURN FALSE;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_has_perm(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_has_perm(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.require_perm(p_perm TEXT)
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;
  IF NOT public.admin_has_perm(p_perm) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;
  RETURN v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.require_perm(TEXT) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.admin_my_permissions()
RETURNS TEXT[]
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
BEGIN
  SELECT role INTO v_role FROM public.admin_users WHERE id = auth.uid();
  IF v_role IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF v_role = 'super_admin' THEN
    RETURN ARRAY[
      'dashboard', 'users', 'organizers', 'events', 'clans', 'ranking',
      'market', 'moderation', 'dialogs', 'achievements', 'dictionaries',
      'economy_view', 'economy_adjust', 'attendance', 'settings_view',
      'settings_write', 'notifications', 'logs', 'search'
    ];
  ELSIF v_role = 'admin' THEN
    RETURN ARRAY[
      'dashboard', 'users', 'organizers', 'events', 'clans', 'ranking',
      'market', 'moderation', 'dialogs', 'achievements', 'dictionaries',
      'economy_view', 'attendance', 'settings_view', 'notifications',
      'logs', 'search'
    ];
  ELSE
    RETURN ARRAY[
      'dashboard', 'market', 'moderation', 'dialogs', 'logs', 'search'
    ];
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_my_permissions() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_my_permissions() TO authenticated;
