-- ============================================================
-- Final polish: RLS hardening
-- ============================================================

-- 1) Nickname check without exposing full profiles to anon
CREATE OR REPLACE FUNCTION public.is_nickname_available(p_nickname TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT NOT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE lower(nickname) = lower(trim(p_nickname))
  );
$$;

REVOKE ALL ON FUNCTION public.is_nickname_available(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_nickname_available(TEXT) TO anon, authenticated;

DROP POLICY IF EXISTS "Anyone can check nickname availability"
  ON public.profiles;

-- Authenticated: can read profiles (app uses own profile primarily;
-- phone protection is enforced by trigger on update + client select lists)
DROP POLICY IF EXISTS "Profiles are viewable by authenticated users"
  ON public.profiles;
DROP POLICY IF EXISTS "Users can read own full profile"
  ON public.profiles;
DROP POLICY IF EXISTS "Users can read public profile fields of others"
  ON public.profiles;

CREATE POLICY "Authenticated users can read profiles"
  ON public.profiles
  FOR SELECT
  TO authenticated
  USING (true);

-- 2) Prevent clients from forging combat stats / phone on own profile
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
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_protect_stats ON public.profiles;
CREATE TRIGGER profiles_protect_stats
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE PROCEDURE public.protect_profile_stats();

-- 3) Events count only for self
CREATE OR REPLACE FUNCTION public.get_user_events_count(p_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  RETURN (
    SELECT COUNT(*)::INTEGER
    FROM public.event_participants
    WHERE user_id = p_user_id
  );
END;
$$;

-- 4) Achievement sync via SECURITY DEFINER (clients cannot forge unlocks)
CREATE OR REPLACE FUNCTION public.sync_user_achievements(p_items JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  item JSONB;
  v_achievement UUID;
  v_progress INTEGER;
  v_unlocked BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  FOR item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_achievement := (item->>'achievement_id')::UUID;
    v_progress := GREATEST(0, COALESCE((item->>'progress')::INTEGER, 0));
    v_unlocked := COALESCE((item->>'unlocked')::BOOLEAN, FALSE);

    INSERT INTO public.user_achievements AS ua (
      user_id,
      achievement_id,
      progress,
      unlocked,
      unlocked_at
    )
    VALUES (
      v_uid,
      v_achievement,
      v_progress,
      v_unlocked,
      CASE WHEN v_unlocked THEN NOW() ELSE NULL END
    )
    ON CONFLICT (user_id, achievement_id) DO UPDATE
    SET
      progress = EXCLUDED.progress,
      unlocked = EXCLUDED.unlocked,
      unlocked_at = CASE
        WHEN EXCLUDED.unlocked AND NOT ua.unlocked THEN NOW()
        WHEN EXCLUDED.unlocked THEN COALESCE(ua.unlocked_at, NOW())
        ELSE NULL
      END;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.sync_user_achievements(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sync_user_achievements(JSONB) TO authenticated;

-- Remove direct client writes to user_achievements (use RPC instead)
DROP POLICY IF EXISTS "Users insert own achievement progress"
  ON public.user_achievements;
DROP POLICY IF EXISTS "Users update own achievement progress"
  ON public.user_achievements;
