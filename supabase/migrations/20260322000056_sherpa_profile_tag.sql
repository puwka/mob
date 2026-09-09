-- ============================================================
-- Display-only profile tag: sherpa (Шерп) — no permissions
-- ============================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS profile_tag TEXT;

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_profile_tag_check;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_profile_tag_check
  CHECK (profile_tag IS NULL OR profile_tag IN ('sherpa'));

-- Clients cannot change profile_tag
CREATE OR REPLACE FUNCTION public.protect_profile_role_and_qr()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.role := 'user';
    NEW.profile_tag := NULL;
    IF NEW.public_qr_id IS NULL THEN
      NEW.public_qr_id := gen_random_uuid();
    END IF;
    IF NEW.status IS NULL THEN
      NEW.status := 'active';
    END IF;
    RETURN NEW;
  END IF;

  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    NEW.role := OLD.role;
    NEW.public_qr_id := OLD.public_qr_id;
    NEW.status := OLD.status;
    NEW.profile_tag := OLD.profile_tag;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.protect_profile_stats()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE'
     AND auth.uid() = NEW.id
     AND NOT public.is_admin() THEN
    NEW.games_played := OLD.games_played;
    NEW.wins := OLD.wins;
    NEW.rating := OLD.rating;
    NEW.polygons_visited := OLD.polygons_visited;
    NEW.phone := OLD.phone;
    NEW.created_at := OLD.created_at;
    NEW.role := OLD.role;
    NEW.public_qr_id := OLD.public_qr_id;
    NEW.status := OLD.status;
    NEW.profile_tag := OLD.profile_tag;
  END IF;
  RETURN NEW;
END;
$$;

-- Badge: admin > moderator > organizer > sherpa > user
CREATE OR REPLACE FUNCTION public.profile_badge_role(p_user_id UUID)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN EXISTS (
      SELECT 1 FROM public.admin_users au
      WHERE au.id = p_user_id AND au.role IN ('super_admin', 'admin')
    ) THEN 'admin'
    WHEN EXISTS (
      SELECT 1 FROM public.admin_users au
      WHERE au.id = p_user_id AND au.role = 'moderator'
    ) THEN 'moderator'
    WHEN (
      SELECT p.role FROM public.profiles p WHERE p.id = p_user_id
    ) = 'organizer' THEN 'organizer'
    WHEN (
      SELECT p.profile_tag FROM public.profiles p WHERE p.id = p_user_id
    ) = 'sherpa' THEN 'sherpa'
    ELSE 'user'
  END;
$$;

CREATE OR REPLACE FUNCTION public.admin_get_profile_tag(p_user_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tag TEXT;
BEGIN
  PERFORM public.require_admin('admin');

  SELECT profile_tag INTO v_tag
  FROM public.profiles
  WHERE id = p_user_id;

  RETURN v_tag;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_profile_tag(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_profile_tag(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_profile_tag(
  p_user_id UUID,
  p_tag TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_tag TEXT := NULLIF(lower(btrim(COALESCE(p_tag, ''))), '');
  v_old TEXT;
  v_new TEXT;
BEGIN
  v_admin := public.require_admin('admin');

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_USER' USING ERRCODE = 'P0001';
  END IF;

  IF v_tag IS NOT NULL AND v_tag NOT IN ('sherpa') THEN
    RAISE EXCEPTION 'INVALID_PROFILE_TAG' USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  SELECT profile_tag INTO v_old
  FROM public.profiles
  WHERE id = p_user_id
  FOR UPDATE;

  UPDATE public.profiles
  SET profile_tag = v_tag
  WHERE id = p_user_id
  RETURNING profile_tag INTO v_new;

  PERFORM public.write_admin_audit(
    v_admin,
    'set_profile_tag',
    'profile',
    p_user_id::TEXT,
    jsonb_build_object('profile_tag', v_old),
    jsonb_build_object('profile_tag', v_new)
  );

  RETURN v_new;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_profile_tag(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_profile_tag(UUID, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
