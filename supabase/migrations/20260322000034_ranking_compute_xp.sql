-- ============================================================
-- Ranking RPCs: score = live XP (same formula as Flutter XpService)
-- Does not rely on stale profiles.rating / clans.rating alone.
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

-- Align with Flutter EventRepository.getUserEventsCount
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
  WHERE user_id = p_user_id
    AND registration_status = 'registered';

  v_xp := public.compute_player_xp(v_games, v_wins, v_polygons, v_events);

  UPDATE public.profiles
  SET rating = v_xp
  WHERE id = p_user_id
    AND rating IS DISTINCT FROM v_xp;

  RETURN v_xp;
END;
$$;

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
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
      PERFORM public.sync_player_rating_from_xp(OLD.user_id);
      PERFORM public.sync_player_rating_from_xp(NEW.user_id);
    ELSIF NEW.registration_status IS DISTINCT FROM OLD.registration_status THEN
      PERFORM public.sync_player_rating_from_xp(NEW.user_id);
    END IF;
    RETURN NEW;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS event_participants_sync_rating_xp ON public.event_participants;
CREATE TRIGGER event_participants_sync_rating_xp
  AFTER INSERT OR DELETE OR UPDATE OF user_id, registration_status
  ON public.event_participants
  FOR EACH ROW
  EXECUTE PROCEDURE public.trg_event_participants_sync_rating_xp();

CREATE OR REPLACE FUNCTION public.ranking_players(
  p_city TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 20,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  nickname TEXT,
  avatar_url TEXT,
  city TEXT,
  rating INTEGER,
  rank BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH event_counts AS (
    SELECT ep.user_id, COUNT(*)::INTEGER AS cnt
    FROM public.event_participants ep
    WHERE ep.registration_status = 'registered'
    GROUP BY ep.user_id
  ),
  filtered AS (
    SELECT
      p.id,
      p.nickname,
      p.avatar_url,
      p.city,
      public.compute_player_xp(
        p.games_played,
        p.wins,
        p.polygons_visited,
        COALESCE(ec.cnt, 0)
      ) AS rating
    FROM public.profiles p
    LEFT JOIN event_counts ec ON ec.user_id = p.id
    WHERE p_city IS NULL
       OR btrim(p_city) = ''
       OR p.city = btrim(p_city)
  ),
  ranked AS (
    SELECT
      f.*,
      RANK() OVER (ORDER BY f.rating DESC, f.nickname ASC, f.id ASC) AS rank
    FROM filtered f
  )
  SELECT
    r.id,
    r.nickname,
    r.avatar_url,
    r.city,
    r.rating,
    r.rank
  FROM ranked r
  ORDER BY r.rank, r.id
  LIMIT GREATEST(COALESCE(p_limit, 20), 1)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
$$;

REVOKE ALL ON FUNCTION public.ranking_players(TEXT, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ranking_players(TEXT, INTEGER, INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION public.ranking_my_player(
  p_city TEXT DEFAULT NULL
)
RETURNS TABLE (
  id UUID,
  nickname TEXT,
  avatar_url TEXT,
  city TEXT,
  rating INTEGER,
  rank BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH event_counts AS (
    SELECT ep.user_id, COUNT(*)::INTEGER AS cnt
    FROM public.event_participants ep
    WHERE ep.registration_status = 'registered'
    GROUP BY ep.user_id
  ),
  filtered AS (
    SELECT
      p.id,
      p.nickname,
      p.avatar_url,
      p.city,
      public.compute_player_xp(
        p.games_played,
        p.wins,
        p.polygons_visited,
        COALESCE(ec.cnt, 0)
      ) AS rating
    FROM public.profiles p
    LEFT JOIN event_counts ec ON ec.user_id = p.id
    WHERE p_city IS NULL
       OR btrim(p_city) = ''
       OR p.city = btrim(p_city)
  ),
  ranked AS (
    SELECT
      f.*,
      RANK() OVER (ORDER BY f.rating DESC, f.nickname ASC, f.id ASC) AS rank
    FROM filtered f
  )
  SELECT
    r.id,
    r.nickname,
    r.avatar_url,
    r.city,
    r.rating,
    r.rank
  FROM ranked r
  WHERE r.id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.ranking_my_player(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ranking_my_player(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.ranking_clans(
  p_city TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 20,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  name TEXT,
  tag TEXT,
  avatar_url TEXT,
  rating INTEGER,
  members_count INTEGER,
  rank BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH event_counts AS (
    SELECT ep.user_id, COUNT(*)::INTEGER AS cnt
    FROM public.event_participants ep
    WHERE ep.registration_status = 'registered'
    GROUP BY ep.user_id
  ),
  member_xp AS (
    SELECT
      cm.clan_id,
      SUM(
        public.compute_player_xp(
          p.games_played,
          p.wins,
          p.polygons_visited,
          COALESCE(ec.cnt, 0)
        )
      )::INTEGER AS xp_sum,
      COUNT(*)::INTEGER AS members_count
    FROM public.clan_members cm
    JOIN public.profiles p ON p.id = cm.user_id
    LEFT JOIN event_counts ec ON ec.user_id = p.id
    GROUP BY cm.clan_id
  ),
  filtered AS (
    SELECT
      c.id,
      c.name,
      c.tag,
      c.avatar_url,
      COALESCE(mx.xp_sum, 0) AS rating,
      COALESCE(mx.members_count, 0) AS members_count
    FROM public.clans c
    LEFT JOIN member_xp mx ON mx.clan_id = c.id
    LEFT JOIN public.profiles lp ON lp.id = c.leader_id
    WHERE p_city IS NULL
       OR btrim(p_city) = ''
       OR lp.city = btrim(p_city)
  ),
  ranked AS (
    SELECT
      f.*,
      RANK() OVER (ORDER BY f.rating DESC, f.name ASC, f.id ASC) AS rank
    FROM filtered f
  )
  SELECT
    r.id,
    r.name,
    r.tag,
    r.avatar_url,
    r.rating,
    r.members_count,
    r.rank
  FROM ranked r
  ORDER BY r.rank, r.id
  LIMIT GREATEST(COALESCE(p_limit, 20), 1)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
$$;

REVOKE ALL ON FUNCTION public.ranking_clans(TEXT, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ranking_clans(TEXT, INTEGER, INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION public.ranking_my_clan(
  p_city TEXT DEFAULT NULL
)
RETURNS TABLE (
  id UUID,
  name TEXT,
  tag TEXT,
  avatar_url TEXT,
  rating INTEGER,
  members_count INTEGER,
  rank BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH my_clan AS (
    SELECT cm.clan_id
    FROM public.clan_members cm
    WHERE cm.user_id = auth.uid()
    LIMIT 1
  ),
  event_counts AS (
    SELECT ep.user_id, COUNT(*)::INTEGER AS cnt
    FROM public.event_participants ep
    WHERE ep.registration_status = 'registered'
    GROUP BY ep.user_id
  ),
  member_xp AS (
    SELECT
      cm.clan_id,
      SUM(
        public.compute_player_xp(
          p.games_played,
          p.wins,
          p.polygons_visited,
          COALESCE(ec.cnt, 0)
        )
      )::INTEGER AS xp_sum,
      COUNT(*)::INTEGER AS members_count
    FROM public.clan_members cm
    JOIN public.profiles p ON p.id = cm.user_id
    LEFT JOIN event_counts ec ON ec.user_id = p.id
    GROUP BY cm.clan_id
  ),
  filtered AS (
    SELECT
      c.id,
      c.name,
      c.tag,
      c.avatar_url,
      COALESCE(mx.xp_sum, 0) AS rating,
      COALESCE(mx.members_count, 0) AS members_count
    FROM public.clans c
    LEFT JOIN member_xp mx ON mx.clan_id = c.id
    LEFT JOIN public.profiles lp ON lp.id = c.leader_id
    WHERE p_city IS NULL
       OR btrim(p_city) = ''
       OR lp.city = btrim(p_city)
  ),
  ranked AS (
    SELECT
      f.*,
      RANK() OVER (ORDER BY f.rating DESC, f.name ASC, f.id ASC) AS rank
    FROM filtered f
  )
  SELECT
    r.id,
    r.name,
    r.tag,
    r.avatar_url,
    r.rating,
    r.members_count,
    r.rank
  FROM ranked r
  JOIN my_clan mc ON mc.clan_id = r.id;
$$;

REVOKE ALL ON FUNCTION public.ranking_my_clan(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ranking_my_clan(TEXT) TO authenticated;

-- Keep stored columns in sync for admin / profile cards
DO $$
DECLARE
  r RECORD;
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc
    WHERE proname = 'sync_player_rating_from_xp'
      AND pg_function_is_visible(oid)
  ) THEN
    FOR r IN SELECT id FROM public.profiles LOOP
      PERFORM public.sync_player_rating_from_xp(r.id);
    END LOOP;
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_proc
    WHERE proname = 'recompute_clan_rating'
      AND pg_function_is_visible(oid)
  ) THEN
    FOR r IN SELECT id FROM public.clans LOOP
      PERFORM public.recompute_clan_rating(r.id);
    END LOOP;
  END IF;
END;
$$;
