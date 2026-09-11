-- ============================================================
-- Admin can set total XP via profiles.bonus_xp
-- Total XP = activity formula + bonus_xp (stored in profiles.rating)
-- ============================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS bonus_xp INTEGER NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.profiles.bonus_xp IS
  'Admin XP adjustment; total XP = compute_player_xp(...) + bonus_xp';
COMMENT ON COLUMN public.profiles.rating IS
  'Player ranking score = XP (activity formula + bonus_xp)';

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
  v_bonus INTEGER;
  v_events INTEGER;
  v_xp INTEGER;
BEGIN
  SELECT
    games_played,
    wins,
    polygons_visited,
    bonus_xp
  INTO v_games, v_wins, v_polygons, v_bonus
  FROM public.profiles
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  SELECT COUNT(*)::INTEGER INTO v_events
  FROM public.event_participants
  WHERE user_id = p_user_id
    AND registration_status = 'registered';

  v_xp := public.compute_player_xp(v_games, v_wins, v_polygons, v_events)
    + COALESCE(v_bonus, 0);
  v_xp := GREATEST(0, v_xp);

  UPDATE public.profiles
  SET rating = v_xp
  WHERE id = p_user_id
    AND rating IS DISTINCT FROM v_xp;

  RETURN v_xp;
END;
$$;

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
       OR NEW.bonus_xp IS DISTINCT FROM OLD.bonus_xp
     ) THEN
    PERFORM public.sync_player_rating_from_xp(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_sync_rating_xp_au ON public.profiles;
CREATE TRIGGER profiles_sync_rating_xp_au
  AFTER UPDATE OF games_played, wins, polygons_visited, bonus_xp ON public.profiles
  FOR EACH ROW
  EXECUTE PROCEDURE public.trg_profiles_sync_rating_xp();

-- Set absolute total XP by adjusting bonus_xp (NULL = re-sync only)
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
  v_old public.profiles;
  v_row public.profiles;
  v_events INTEGER;
  v_base INTEGER;
  v_bonus INTEGER;
BEGIN
  v_admin := public.require_admin('moderator');

  SELECT * INTO v_old FROM public.profiles WHERE id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF p_rating IS NOT NULL THEN
    IF p_rating < 0 THEN
      RAISE EXCEPTION 'INVALID_RATING' USING ERRCODE = 'P0001';
    END IF;

    SELECT COUNT(*)::INTEGER INTO v_events
    FROM public.event_participants
    WHERE user_id = p_user_id
      AND registration_status = 'registered';

    v_base := public.compute_player_xp(
      v_old.games_played,
      v_old.wins,
      v_old.polygons_visited,
      v_events
    );
    v_bonus := p_rating - v_base;

    UPDATE public.profiles
    SET bonus_xp = v_bonus
    WHERE id = p_user_id;
  END IF;

  PERFORM public.sync_player_rating_from_xp(p_user_id);
  SELECT * INTO v_row FROM public.profiles WHERE id = p_user_id;

  PERFORM public.write_admin_audit(
    v_admin,
    CASE WHEN p_rating IS NULL THEN 'sync_player_xp' ELSE 'set_player_xp' END,
    'profile',
    p_user_id::TEXT,
    jsonb_build_object(
      'rating_xp', v_old.rating,
      'bonus_xp', v_old.bonus_xp
    ),
    jsonb_build_object(
      'rating_xp', v_row.rating,
      'bonus_xp', v_row.bonus_xp,
      'requested_xp', p_rating
    )
  );

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_player_rating(UUID, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_player_rating(UUID, INTEGER) TO authenticated;

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
  v_events INTEGER;
  v_base INTEGER;
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

  IF p_rating IS NOT NULL AND p_rating < 0 THEN
    RAISE EXCEPTION 'INVALID_RATING' USING ERRCODE = 'P0001';
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

  IF p_rating IS NOT NULL THEN
    SELECT COUNT(*)::INTEGER INTO v_events
    FROM public.event_participants
    WHERE user_id = p_user_id
      AND registration_status = 'registered';

    v_base := public.compute_player_xp(
      v_new.games_played,
      v_new.wins,
      v_new.polygons_visited,
      v_events
    );

    UPDATE public.profiles
    SET bonus_xp = p_rating - v_base
    WHERE id = p_user_id;
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

-- Ranking: include bonus_xp in live XP
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
      GREATEST(
        0,
        public.compute_player_xp(
          p.games_played,
          p.wins,
          p.polygons_visited,
          COALESCE(ec.cnt, 0)
        ) + COALESCE(p.bonus_xp, 0)
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
      GREATEST(
        0,
        public.compute_player_xp(
          p.games_played,
          p.wins,
          p.polygons_visited,
          COALESCE(ec.cnt, 0)
        ) + COALESCE(p.bonus_xp, 0)
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
        GREATEST(
          0,
          public.compute_player_xp(
            p.games_played,
            p.wins,
            p.polygons_visited,
            COALESCE(ec.cnt, 0)
          ) + COALESCE(p.bonus_xp, 0)
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
        GREATEST(
          0,
          public.compute_player_xp(
            p.games_played,
            p.wins,
            p.polygons_visited,
            COALESCE(ec.cnt, 0)
          ) + COALESCE(p.bonus_xp, 0)
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
  WHERE r.id = (SELECT clan_id FROM my_clan);
$$;
