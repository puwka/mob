-- ============================================================
-- App roles (user | organizer) + public QR id
-- Existing free-text profiles.role → game_role (in-game loadout)
-- ============================================================

-- 1) Preserve combat/game role, free the `role` name for app roles
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'profiles'
      AND column_name = 'role'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'profiles'
      AND column_name = 'game_role'
  ) THEN
    ALTER TABLE public.profiles RENAME COLUMN role TO game_role;
  END IF;
END $$;

-- 2) App role
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS role TEXT;

UPDATE public.profiles
SET role = 'user'
WHERE role IS NULL OR role NOT IN ('user', 'organizer');

ALTER TABLE public.profiles
  ALTER COLUMN role SET DEFAULT 'user',
  ALTER COLUMN role SET NOT NULL;

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_role_check
  CHECK (role IN ('user', 'organizer'));

CREATE INDEX IF NOT EXISTS profiles_role_idx ON public.profiles (role);

-- 3) Public QR token (no secrets)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS public_qr_id UUID;

UPDATE public.profiles
SET public_qr_id = gen_random_uuid()
WHERE public_qr_id IS NULL;

ALTER TABLE public.profiles
  ALTER COLUMN public_qr_id SET DEFAULT gen_random_uuid(),
  ALTER COLUMN public_qr_id SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS profiles_public_qr_id_uidx
  ON public.profiles (public_qr_id);

-- 4) Force safe defaults on insert; lock role + qr on client update
CREATE OR REPLACE FUNCTION public.protect_profile_role_and_qr()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.role := 'user';
    IF NEW.public_qr_id IS NULL THEN
      NEW.public_qr_id := gen_random_uuid();
    END IF;
    RETURN NEW;
  END IF;

  -- Clients (authenticated JWT) cannot change app role or QR token
  IF auth.uid() IS NOT NULL THEN
    NEW.role := OLD.role;
    NEW.public_qr_id := OLD.public_qr_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_protect_role_qr ON public.profiles;
CREATE TRIGGER profiles_protect_role_qr
  BEFORE INSERT OR UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE PROCEDURE public.protect_profile_role_and_qr();

-- Keep combat stats protection; also lock role/qr as belt-and-suspenders
CREATE OR REPLACE FUNCTION public.protect_profile_stats()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND auth.uid() = NEW.id THEN
    NEW.games_played := OLD.games_played;
    NEW.wins := OLD.wins;
    NEW.rating := OLD.rating;
    NEW.polygons_visited := OLD.polygons_visited;
    NEW.phone := OLD.phone;
    NEW.created_at := OLD.created_at;
    NEW.role := OLD.role;
    NEW.public_qr_id := OLD.public_qr_id;
  END IF;
  RETURN NEW;
END;
$$;

-- 5) Column grants: clients cannot UPDATE role / public_qr_id
REVOKE UPDATE ON public.profiles FROM authenticated;
GRANT UPDATE (
  nickname,
  city,
  avatar_url,
  bio,
  game_role,
  team_name
) ON public.profiles TO authenticated;

-- 6) Helper for RLS
CREATE OR REPLACE FUNCTION public.is_organizer()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = auth.uid()
      AND role = 'organizer'
  );
$$;

REVOKE ALL ON FUNCTION public.is_organizer() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_organizer() TO authenticated;

-- 7) Admin-only role assignment (service_role / SQL Editor — NOT authenticated)
CREATE OR REPLACE FUNCTION public.admin_set_app_role(
  p_user_id UUID,
  p_role TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_role IS NULL OR p_role NOT IN ('user', 'organizer') THEN
    RAISE EXCEPTION 'INVALID_ROLE' USING ERRCODE = 'P0001';
  END IF;

  -- Block JWT authenticated clients; allow service_role / postgres / SQL editor
  IF auth.role() = 'authenticated' THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  UPDATE public.profiles
  SET role = p_role
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_app_role(UUID, TEXT) FROM PUBLIC;
-- Intentionally NOT granted to authenticated / anon

-- Lookup by QR token (for future scanner; no secrets returned beyond public card)
CREATE OR REPLACE FUNCTION public.lookup_profile_by_qr(p_qr_id UUID)
RETURNS TABLE (
  id UUID,
  nickname TEXT,
  city TEXT,
  avatar_url TEXT,
  public_qr_id UUID
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  -- Only organizers may resolve QR → profile
  IF NOT public.is_organizer() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT p.id, p.nickname, p.city, p.avatar_url, p.public_qr_id
  FROM public.profiles p
  WHERE p.public_qr_id = p_qr_id
  LIMIT 1;
END;
$$;

REVOKE ALL ON FUNCTION public.lookup_profile_by_qr(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lookup_profile_by_qr(UUID) TO authenticated;

-- 8) Events: only organizers create/edit own events
DROP POLICY IF EXISTS "Organizers can create events" ON public.events;
CREATE POLICY "Organizers can create events"
  ON public.events
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.is_organizer()
    AND organizer_id = auth.uid()
  );

DROP POLICY IF EXISTS "Organizers can update own events" ON public.events;
CREATE POLICY "Organizers can update own events"
  ON public.events
  FOR UPDATE
  TO authenticated
  USING (public.is_organizer() AND organizer_id = auth.uid())
  WITH CHECK (public.is_organizer() AND organizer_id = auth.uid());

DROP POLICY IF EXISTS "Organizers can delete own events" ON public.events;
CREATE POLICY "Organizers can delete own events"
  ON public.events
  FOR DELETE
  TO authenticated
  USING (public.is_organizer() AND organizer_id = auth.uid());

COMMENT ON COLUMN public.profiles.role IS 'App role: user | organizer (client cannot self-elevate)';
COMMENT ON COLUMN public.profiles.game_role IS 'In-game loadout/role label (editable)';
COMMENT ON COLUMN public.profiles.public_qr_id IS 'Public token encoded in participant QR (no secrets)';
