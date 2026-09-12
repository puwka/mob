-- ============================================================
-- Recreate clans_with_stats so it includes clans.city
-- (Postgres expands c.* at CREATE time; city was added later in 000054)
-- Also filter regional clan ranking by clan.city, not leader profile city.
-- ============================================================

-- REPLACE cannot reorder/rename columns — drop first.
DROP VIEW IF EXISTS public.clans_with_stats;

CREATE VIEW public.clans_with_stats AS
SELECT
  c.*,
  (SELECT COUNT(*)::INTEGER FROM public.clan_members cm WHERE cm.clan_id = c.id) AS members_count,
  lp.nickname AS leader_nickname
FROM public.clans c
LEFT JOIN public.profiles lp ON lp.id = c.leader_id;

GRANT SELECT ON public.clans_with_stats TO authenticated;

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
    WHERE p_city IS NULL
       OR btrim(p_city) = ''
       OR c.city = btrim(p_city)
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
    WHERE p_city IS NULL
       OR btrim(p_city) = ''
       OR c.city = btrim(p_city)
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
