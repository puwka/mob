-- Fix admin_recent_activity: aggregate + ORDER BY without subquery
CREATE OR REPLACE FUNCTION public.admin_recent_activity(p_limit INTEGER DEFAULT 20)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);
BEGIN
  PERFORM public.require_admin('moderator');

  RETURN (
    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'kind', x.kind,
          'entity_id', x.entity_id,
          'title', x.title,
          'at', x.at
        )
        ORDER BY x.at DESC NULLS LAST
      ),
      '[]'::jsonb
    )
    FROM (
      SELECT *
      FROM (
        (
          SELECT
            'new_user'::TEXT AS kind,
            p.id::TEXT AS entity_id,
            p.nickname AS title,
            p.created_at AS at
          FROM public.profiles p
          ORDER BY p.created_at DESC
          LIMIT v_limit
        )
        UNION ALL
        (
          SELECT
            'new_event'::TEXT,
            e.id::TEXT,
            e.title,
            e.created_at
          FROM public.events e
          ORDER BY e.created_at DESC
          LIMIT v_limit
        )
        UNION ALL
        (
          SELECT
            'clan_join_request'::TEXT,
            r.id::TEXT,
            COALESCE(c.name, 'Clan') || ' ← ' || COALESCE(pr.nickname, 'user'),
            r.created_at
          FROM public.clan_join_requests r
          LEFT JOIN public.clans c ON c.id = r.clan_id
          LEFT JOIN public.profiles pr ON pr.id = r.user_id
          WHERE r.status = 'pending'
          ORDER BY r.created_at DESC
          LIMIT v_limit
        )
        UNION ALL
        (
          SELECT
            'new_listing'::TEXT,
            l.id::TEXT,
            l.title,
            l.created_at
          FROM public.listings l
          ORDER BY l.created_at DESC
          LIMIT v_limit
        )
        UNION ALL
        (
          SELECT
            'achievement_unlock'::TEXT,
            ua.user_id::TEXT || ':' || ua.achievement_id::TEXT,
            COALESCE(a.title, 'Achievement') || ' — ' || COALESCE(pr.nickname, ''),
            ua.unlocked_at
          FROM public.user_achievements ua
          LEFT JOIN public.achievements a ON a.id = ua.achievement_id
          LEFT JOIN public.profiles pr ON pr.id = ua.user_id
          WHERE ua.unlocked = true AND ua.unlocked_at IS NOT NULL
          ORDER BY ua.unlocked_at DESC
          LIMIT v_limit
        )
      ) u
      ORDER BY u.at DESC NULLS LAST
      LIMIT v_limit
    ) x
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_recent_activity(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_recent_activity(INTEGER) TO authenticated;
