-- ============================================================
-- Dating questionnaire (preferences) required before feed
-- ============================================================

CREATE TABLE IF NOT EXISTS public.dating_preferences (
  user_id UUID PRIMARY KEY REFERENCES public.profiles (id) ON DELETE CASCADE,
  gender TEXT NOT NULL CHECK (gender IN ('male', 'female')),
  birth_date DATE NOT NULL,
  looking_for TEXT NOT NULL CHECK (looking_for IN ('male', 'female', 'any')),
  age_min INTEGER NOT NULL DEFAULT 18
    CHECK (age_min >= 18 AND age_min <= 80),
  age_max INTEGER NOT NULL DEFAULT 45
    CHECK (age_max >= 18 AND age_max <= 80),
  city TEXT NOT NULL,
  about TEXT,
  completed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT dating_preferences_age_range CHECK (age_min <= age_max),
  CONSTRAINT dating_preferences_adult CHECK (
    birth_date <= (CURRENT_DATE - INTERVAL '18 years')
  ),
  CONSTRAINT dating_preferences_about_len CHECK (
    about IS NULL OR char_length(about) <= 300
  ),
  CONSTRAINT dating_preferences_city_len CHECK (
    char_length(btrim(city)) BETWEEN 2 AND 80
  )
);

CREATE INDEX IF NOT EXISTS dating_preferences_city_idx
  ON public.dating_preferences (lower(city));

CREATE INDEX IF NOT EXISTS dating_preferences_gender_idx
  ON public.dating_preferences (gender);

ALTER TABLE public.dating_preferences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Dating prefs select authenticated"
  ON public.dating_preferences;
CREATE POLICY "Dating prefs select authenticated"
  ON public.dating_preferences
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Dating prefs upsert own"
  ON public.dating_preferences;
CREATE POLICY "Dating prefs upsert own"
  ON public.dating_preferences
  FOR ALL
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.dating_age_years(p_birth_date DATE)
RETURNS INTEGER
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT GREATEST(
    0,
    EXTRACT(YEAR FROM age(CURRENT_DATE, p_birth_date))::INTEGER
  );
$$;

CREATE OR REPLACE FUNCTION public.get_my_dating_preferences()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_row public.dating_preferences;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_row
  FROM public.dating_preferences
  WHERE user_id = v_uid;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object(
    'user_id', v_row.user_id,
    'gender', v_row.gender,
    'birth_date', v_row.birth_date,
    'age', public.dating_age_years(v_row.birth_date),
    'looking_for', v_row.looking_for,
    'age_min', v_row.age_min,
    'age_max', v_row.age_max,
    'city', v_row.city,
    'about', v_row.about,
    'completed_at', v_row.completed_at,
    'updated_at', v_row.updated_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_dating_preferences() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_dating_preferences() TO authenticated;

CREATE OR REPLACE FUNCTION public.upsert_dating_preferences(
  p_gender TEXT,
  p_birth_date DATE,
  p_looking_for TEXT,
  p_age_min INTEGER,
  p_age_max INTEGER,
  p_city TEXT,
  p_about TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_gender TEXT := lower(btrim(COALESCE(p_gender, '')));
  v_looking TEXT := lower(btrim(COALESCE(p_looking_for, '')));
  v_city TEXT := btrim(COALESCE(p_city, ''));
  v_about TEXT := NULLIF(btrim(COALESCE(p_about, '')), '');
  v_row public.dating_preferences;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF v_gender NOT IN ('male', 'female') THEN
    RAISE EXCEPTION 'INVALID_GENDER' USING ERRCODE = 'P0001';
  END IF;

  IF v_looking NOT IN ('male', 'female', 'any') THEN
    RAISE EXCEPTION 'INVALID_LOOKING_FOR' USING ERRCODE = 'P0001';
  END IF;

  IF p_birth_date IS NULL THEN
    RAISE EXCEPTION 'INVALID_BIRTH_DATE' USING ERRCODE = 'P0001';
  END IF;

  IF p_birth_date > (CURRENT_DATE - INTERVAL '18 years') THEN
    RAISE EXCEPTION 'MUST_BE_ADULT' USING ERRCODE = 'P0001';
  END IF;

  IF p_birth_date < DATE '1940-01-01' THEN
    RAISE EXCEPTION 'INVALID_BIRTH_DATE' USING ERRCODE = 'P0001';
  END IF;

  IF p_age_min IS NULL OR p_age_max IS NULL
     OR p_age_min < 18 OR p_age_max > 80 OR p_age_min > p_age_max THEN
    RAISE EXCEPTION 'INVALID_AGE_RANGE' USING ERRCODE = 'P0001';
  END IF;

  IF char_length(v_city) < 2 OR char_length(v_city) > 80 THEN
    RAISE EXCEPTION 'INVALID_CITY' USING ERRCODE = 'P0001';
  END IF;

  IF v_about IS NOT NULL AND char_length(v_about) > 300 THEN
    RAISE EXCEPTION 'ABOUT_TOO_LONG' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.dating_preferences (
    user_id, gender, birth_date, looking_for,
    age_min, age_max, city, about, completed_at, updated_at
  )
  VALUES (
    v_uid, v_gender, p_birth_date, v_looking,
    p_age_min, p_age_max, v_city, v_about, NOW(), NOW()
  )
  ON CONFLICT (user_id) DO UPDATE SET
    gender = EXCLUDED.gender,
    birth_date = EXCLUDED.birth_date,
    looking_for = EXCLUDED.looking_for,
    age_min = EXCLUDED.age_min,
    age_max = EXCLUDED.age_max,
    city = EXCLUDED.city,
    about = EXCLUDED.about,
    updated_at = NOW()
  RETURNING * INTO v_row;

  RETURN jsonb_build_object(
    'user_id', v_row.user_id,
    'gender', v_row.gender,
    'birth_date', v_row.birth_date,
    'age', public.dating_age_years(v_row.birth_date),
    'looking_for', v_row.looking_for,
    'age_min', v_row.age_min,
    'age_max', v_row.age_max,
    'city', v_row.city,
    'about', v_row.about,
    'completed_at', v_row.completed_at,
    'updated_at', v_row.updated_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_dating_preferences(TEXT, DATE, TEXT, INTEGER, INTEGER, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_dating_preferences(TEXT, DATE, TEXT, INTEGER, INTEGER, TEXT, TEXT) TO authenticated;

-- Feed uses preferences; requires completed questionnaire.
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
  v_city_override TEXT := NULLIF(btrim(COALESCE(p_city, '')), '');
  v_me public.dating_preferences;
  v_my_age INTEGER;
  v_filter_city TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_me
  FROM public.dating_preferences
  WHERE user_id = v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'DATING_PREFS_REQUIRED' USING ERRCODE = 'P0001';
  END IF;

  v_my_age := public.dating_age_years(v_me.birth_date);
  v_filter_city := COALESCE(v_city_override, v_me.city);

  RETURN COALESCE(
    (
      SELECT jsonb_agg(row_data ORDER BY sort_key)
      FROM (
        SELECT
          jsonb_build_object(
            'id', p.id,
            'nickname', p.nickname,
            'city', pref.city,
            'avatar_url', p.avatar_url,
            'age', public.dating_age_years(pref.birth_date),
            'gender', pref.gender,
            'about', pref.about,
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
        JOIN public.dating_preferences pref ON pref.user_id = p.id
        WHERE p.id <> v_uid
          AND NOT public.is_users_blocked(v_uid, p.id)
          AND lower(pref.city) = lower(v_filter_city)
          -- I look for their gender
          AND (
            v_me.looking_for = 'any'
            OR pref.gender = v_me.looking_for
          )
          -- They look for my gender
          AND (
            pref.looking_for = 'any'
            OR pref.looking_for = v_me.gender
          )
          -- Age filters (mutual)
          AND public.dating_age_years(pref.birth_date)
                BETWEEN v_me.age_min AND v_me.age_max
          AND v_my_age BETWEEN pref.age_min AND pref.age_max
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

-- Seed prefs for existing dating test users (if present)
INSERT INTO public.dating_preferences (
  user_id, gender, birth_date, looking_for, age_min, age_max, city, about
)
SELECT
  p.id,
  CASE WHEN length(p.nickname) % 2 = 0 THEN 'male' ELSE 'female' END,
  (CURRENT_DATE - make_interval(years => 20 + (length(p.nickname) % 12)))::date,
  'any',
  18,
  50,
  p.city,
  COALESCE(NULLIF(btrim(p.bio), ''), 'Тестовая анкета')
FROM public.profiles p
WHERE p.id BETWEEN
  'a1000000-0000-4000-8000-000000000001'::uuid
  AND 'a1000000-0000-4000-8000-000000000020'::uuid
ON CONFLICT (user_id) DO NOTHING;

NOTIFY pgrst, 'reload schema';
