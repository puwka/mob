-- ============================================================
-- Player rating = XP; clan rating = SUM(member XP)
-- XP formula (must match Flutter XpService):
--   games_played*100 + wins*250 + polygons_visited*100 + events_count*100
-- ============================================================

CREATE OR REPLACE FUNCTION public.compute_player_xp(
  p_games_played INTEGER,
  p_wins INTEGER,
  p_polygons_visited INTEGER,
  p_events_count INTEGER
)
RETURNS INTEGER
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT GREATEST(
    0,
    COALESCE(p_games_played, 0) * 100
      + COALESCE(p_wins, 0) * 250
      + COALESCE(p_polygons_visited, 0) * 100
      + COALESCE(p_events_count, 0) * 100
  );
$$;

CREATE OR REPLACE FUNCTION public.sync_player_rating_from_xp(p_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_games INTEGER;
  v_wins INTEGER;
  v_polygons INTEGER;
  v_events INTEGER;
  v_xp INTEGER;
BEGIN
  SELECT
    games_played,
    wins,
    polygons_visited
  INTO v_games, v_wins, v_polygons
  FROM public.profiles
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  SELECT COUNT(*)::INTEGER INTO v_events
  FROM public.event_participants
  WHERE user_id = p_user_id;

  v_xp := public.compute_player_xp(v_games, v_wins, v_polygons, v_events);

  UPDATE public.profiles
  SET rating = v_xp
  WHERE id = p_user_id
    AND rating IS DISTINCT FROM v_xp;

  RETURN v_xp;
END;
$$;

REVOKE ALL ON FUNCTION public.compute_player_xp(INTEGER, INTEGER, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.compute_player_xp(INTEGER, INTEGER, INTEGER, INTEGER)
  TO anon, authenticated;

REVOKE ALL ON FUNCTION public.sync_player_rating_from_xp(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sync_player_rating_from_xp(UUID) TO authenticated;

-- Keep clan sum semantics; document as XP sum
CREATE OR REPLACE FUNCTION public.recompute_clan_rating(p_clan_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sum INTEGER;
BEGIN
  -- clans.rating = SUM(member profiles.rating) where rating is XP
  SELECT COALESCE(SUM(p.rating), 0)::INTEGER INTO v_sum
  FROM public.clan_members cm
  JOIN public.profiles p ON p.id = cm.user_id
  WHERE cm.clan_id = p_clan_id;

  UPDATE public.clans SET rating = v_sum WHERE id = p_clan_id;
  RETURN v_sum;
END;
$$;

COMMENT ON COLUMN public.profiles.rating IS
  'Player ranking score = XP (games*100 + wins*250 + polygons*100 + events*100)';
COMMENT ON COLUMN public.clans.rating IS
  'Clan ranking = SUM(member XP / profiles.rating) — never set manually';

-- Sync when stats change
CREATE OR REPLACE FUNCTION public.trg_profiles_sync_rating_xp()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE'
     AND (
       NEW.games_played IS DISTINCT FROM OLD.games_played
       OR NEW.wins IS DISTINCT FROM OLD.wins
       OR NEW.polygons_visited IS DISTINCT FROM OLD.polygons_visited
     ) THEN
    PERFORM public.sync_player_rating_from_xp(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_sync_rating_xp_au ON public.profiles;
CREATE TRIGGER profiles_sync_rating_xp_au
  AFTER UPDATE OF games_played, wins, polygons_visited ON public.profiles
  FOR EACH ROW
  EXECUTE PROCEDURE public.trg_profiles_sync_rating_xp();

-- Sync when event participation changes
CREATE OR REPLACE FUNCTION public.trg_event_participants_sync_rating_xp()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.sync_player_rating_from_xp(NEW.user_id);
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    PERFORM public.sync_player_rating_from_xp(OLD.user_id);
    RETURN OLD;
  ELSIF TG_OP = 'UPDATE' AND NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    PERFORM public.sync_player_rating_from_xp(OLD.user_id);
    PERFORM public.sync_player_rating_from_xp(NEW.user_id);
    RETURN NEW;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS event_participants_sync_rating_xp ON public.event_participants;
CREATE TRIGGER event_participants_sync_rating_xp
  AFTER INSERT OR DELETE OR UPDATE OF user_id ON public.event_participants
  FOR EACH ROW
  EXECUTE PROCEDURE public.trg_event_participants_sync_rating_xp();

-- Admin profile update: ignore manual rating, always sync XP
CREATE OR REPLACE FUNCTION public.admin_update_profile(
  p_user_id UUID,
  p_nickname TEXT DEFAULT NULL,
  p_city TEXT DEFAULT NULL,
  p_bio TEXT DEFAULT NULL,
  p_avatar_url TEXT DEFAULT NULL,
  p_clear_bio BOOLEAN DEFAULT FALSE,
  p_clear_avatar BOOLEAN DEFAULT FALSE,
  p_role TEXT DEFAULT NULL,
  p_rating INTEGER DEFAULT NULL,
  p_games_played INTEGER DEFAULT NULL,
  p_wins INTEGER DEFAULT NULL,
  p_polygons_visited INTEGER DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_game_role TEXT DEFAULT NULL,
  p_team_name TEXT DEFAULT NULL
)
RETURNS public.profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_old public.profiles;
  v_new public.profiles;
BEGIN
  v_admin := public.require_admin('moderator');

  SELECT * INTO v_old FROM public.profiles WHERE id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF p_role IS NOT NULL AND p_role IS DISTINCT FROM v_old.role THEN
    PERFORM public.require_admin('admin');
    IF p_role NOT IN ('user', 'organizer') THEN
      RAISE EXCEPTION 'INVALID_ROLE' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  IF p_status IS NOT NULL AND p_status NOT IN ('active', 'blocked') THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.profiles SET
    nickname = COALESCE(NULLIF(trim(p_nickname), ''), nickname),
    city = COALESCE(NULLIF(trim(p_city), ''), city),
    bio = CASE
      WHEN p_clear_bio THEN NULL
      WHEN p_bio IS NOT NULL THEN p_bio
      ELSE bio
    END,
    avatar_url = CASE
      WHEN p_clear_avatar THEN NULL
      WHEN p_avatar_url IS NOT NULL THEN p_avatar_url
      ELSE avatar_url
    END,
    role = COALESCE(p_role, role),
    -- rating is XP-derived; p_rating ignored
    games_played = COALESCE(p_games_played, games_played),
    wins = COALESCE(p_wins, wins),
    polygons_visited = COALESCE(p_polygons_visited, polygons_visited),
    status = COALESCE(p_status, status),
    game_role = COALESCE(p_game_role, game_role),
    team_name = COALESCE(p_team_name, team_name)
  WHERE id = p_user_id
  RETURNING * INTO v_new;

  IF p_role = 'organizer' AND v_old.role IS DISTINCT FROM 'organizer' THEN
    PERFORM public.ensure_organizer_wallet(p_user_id);
  END IF;

  PERFORM public.sync_player_rating_from_xp(p_user_id);
  SELECT * INTO v_new FROM public.profiles WHERE id = p_user_id;

  PERFORM public.write_admin_audit(
    v_admin,
    'update_profile',
    'profile',
    p_user_id::TEXT,
    to_jsonb(v_old),
    to_jsonb(v_new)
  );

  RETURN v_new;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_profile(
  UUID, TEXT, TEXT, TEXT, TEXT, BOOLEAN, BOOLEAN, TEXT,
  INTEGER, INTEGER, INTEGER, INTEGER, TEXT, TEXT, TEXT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_profile(
  UUID, TEXT, TEXT, TEXT, TEXT, BOOLEAN, BOOLEAN, TEXT,
  INTEGER, INTEGER, INTEGER, INTEGER, TEXT, TEXT, TEXT
) TO authenticated;

-- Manual rating setter now only re-syncs XP
CREATE OR REPLACE FUNCTION public.admin_set_player_rating(
  p_user_id UUID,
  p_rating INTEGER DEFAULT NULL
)
RETURNS public.profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_row public.profiles;
BEGIN
  v_admin := public.require_admin('moderator');
  PERFORM public.sync_player_rating_from_xp(p_user_id);
  SELECT * INTO v_row FROM public.profiles WHERE id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;
  PERFORM public.write_admin_audit(
    v_admin,
    'sync_player_xp',
    'profile',
    p_user_id::TEXT,
    NULL,
    jsonb_build_object('rating_xp', v_row.rating)
  );
  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_player_rating(UUID, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_player_rating(UUID, INTEGER) TO authenticated;

-- Backfill all players then clans
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT id FROM public.profiles LOOP
    PERFORM public.sync_player_rating_from_xp(r.id);
  END LOOP;

  FOR r IN SELECT id FROM public.clans LOOP
    PERFORM public.recompute_clan_rating(r.id);
  END LOOP;
END;
$$;
