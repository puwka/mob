-- ============================================================
-- Remove dating questionnaire; feed uses profiles only
-- ============================================================

DROP FUNCTION IF EXISTS public.get_my_dating_preferences();
DROP FUNCTION IF EXISTS public.upsert_dating_preferences(TEXT, DATE, TEXT, INTEGER, INTEGER, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.dating_age_years(DATE);

DROP TABLE IF EXISTS public.dating_preferences;

DROP FUNCTION IF EXISTS public.dating_fetch_candidates(INTEGER);
DROP FUNCTION IF EXISTS public.dating_fetch_candidates(INTEGER, TEXT);

CREATE OR REPLACE FUNCTION public.dating_fetch_candidates(
  p_limit INTEGER DEFAULT 20,
  p_city TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_limit INTEGER := GREATEST(1, LEAST(COALESCE(p_limit, 20), 50));
  v_city TEXT := NULLIF(btrim(COALESCE(p_city, '')), '');
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  RETURN COALESCE(
    (
      SELECT jsonb_agg(row_data ORDER BY sort_key)
      FROM (
        SELECT
          jsonb_build_object(
            'id', p.id,
            'nickname', p.nickname,
            'city', p.city,
            'avatar_url', p.avatar_url,
            'photo_urls', (
              SELECT COALESCE(jsonb_agg(photos.url ORDER BY photos.ord), '[]'::jsonb)
              FROM (
                SELECT raw.url, MIN(raw.ord) AS ord
                FROM (
                  SELECT p.avatar_url AS url, 0 AS ord
                  WHERE p.avatar_url IS NOT NULL AND btrim(p.avatar_url) <> ''
                  UNION ALL
                  SELECT pp.url, pp.sort_order + 1
                  FROM public.profile_photos pp
                  WHERE pp.user_id = p.id
                ) raw
                WHERE raw.url IS NOT NULL AND btrim(raw.url) <> ''
                GROUP BY raw.url
                ORDER BY MIN(raw.ord)
                LIMIT 5
              ) photos
            )
          ) AS row_data,
          p.created_at AS sort_key
        FROM public.profiles p
        WHERE p.id <> v_uid
          AND NOT public.is_users_blocked(v_uid, p.id)
          AND (v_city IS NULL OR lower(p.city) = lower(v_city))
          AND NOT EXISTS (
            SELECT 1
            FROM public.dating_actions da
            WHERE da.from_user_id = v_uid
              AND da.to_user_id = p.id
          )
          AND NOT EXISTS (
            SELECT 1
            FROM public.dating_matches dm
            WHERE (dm.user1_id = v_uid AND dm.user2_id = p.id)
               OR (dm.user2_id = v_uid AND dm.user1_id = p.id)
          )
          AND (
            (p.avatar_url IS NOT NULL AND btrim(p.avatar_url) <> '')
            OR EXISTS (
              SELECT 1 FROM public.profile_photos pp WHERE pp.user_id = p.id
            )
          )
        ORDER BY p.created_at DESC
        LIMIT v_limit
      ) candidates
    ),
    '[]'::jsonb
  );
END;
$$;

REVOKE ALL ON FUNCTION public.dating_fetch_candidates(INTEGER, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dating_fetch_candidates(INTEGER, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
