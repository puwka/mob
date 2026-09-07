-- ============================================================
-- Ranking: paginated players / clans (regional + global)
-- Clan rating remains SUM(member.profiles.rating) via existing triggers.
-- ============================================================

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
  WITH filtered AS (
    SELECT
      p.id,
      p.nickname,
      p.avatar_url,
      p.city,
      p.rating
    FROM public.profiles p
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
  WITH filtered AS (
    SELECT
      p.id,
      p.nickname,
      p.avatar_url,
      p.city,
      p.rating
    FROM public.profiles p
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

-- Regional clans: leader lives in city. Rating = stored computed SUM.
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
  WITH filtered AS (
    SELECT
      c.id,
      c.name,
      c.tag,
      c.avatar_url,
      c.rating,
      (
        SELECT COUNT(*)::INTEGER
        FROM public.clan_members cm
        WHERE cm.clan_id = c.id
      ) AS members_count
    FROM public.clans c
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
  filtered AS (
    SELECT
      c.id,
      c.name,
      c.tag,
      c.avatar_url,
      c.rating,
      (
        SELECT COUNT(*)::INTEGER
        FROM public.clan_members cm
        WHERE cm.clan_id = c.id
      ) AS members_count
    FROM public.clans c
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
