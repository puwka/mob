-- ============================================================
-- Dating (Знакомства): actions + matches scaffold + feed RPCs
-- ============================================================

CREATE TABLE IF NOT EXISTS public.dating_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  from_user_id UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  to_user_id UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  action TEXT NOT NULL CHECK (action IN ('like', 'skip')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT dating_actions_no_self CHECK (from_user_id <> to_user_id),
  CONSTRAINT dating_actions_unique_pair UNIQUE (from_user_id, to_user_id)
);

CREATE INDEX IF NOT EXISTS dating_actions_from_idx
  ON public.dating_actions (from_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS dating_actions_to_idx
  ON public.dating_actions (to_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS dating_actions_from_action_idx
  ON public.dating_actions (from_user_id, action);

ALTER TABLE public.dating_actions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Dating actions insert own" ON public.dating_actions;
CREATE POLICY "Dating actions insert own"
  ON public.dating_actions
  FOR INSERT
  TO authenticated
  WITH CHECK (from_user_id = auth.uid());

DROP POLICY IF EXISTS "Dating actions select own" ON public.dating_actions;
CREATE POLICY "Dating actions select own"
  ON public.dating_actions
  FOR SELECT
  TO authenticated
  USING (from_user_id = auth.uid());

-- No UPDATE / DELETE for clients (actions are final).

-- Prepared for mutual-like matches (UI later).
CREATE TABLE IF NOT EXISTS public.dating_matches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_low UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  user_high UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT dating_matches_ordered CHECK (user_low < user_high),
  CONSTRAINT dating_matches_unique_pair UNIQUE (user_low, user_high)
);

CREATE INDEX IF NOT EXISTS dating_matches_user_low_idx
  ON public.dating_matches (user_low, created_at DESC);

CREATE INDEX IF NOT EXISTS dating_matches_user_high_idx
  ON public.dating_matches (user_high, created_at DESC);

ALTER TABLE public.dating_matches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Dating matches select own" ON public.dating_matches;
CREATE POLICY "Dating matches select own"
  ON public.dating_matches
  FOR SELECT
  TO authenticated
  USING (user_low = auth.uid() OR user_high = auth.uid());

-- Inserts only via SECURITY DEFINER RPCs.

CREATE OR REPLACE FUNCTION public.dating_record_action(
  p_to_user_id UUID,
  p_action TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_action TEXT := lower(btrim(COALESCE(p_action, '')));
  v_row public.dating_actions;
  v_matched BOOLEAN := FALSE;
  v_low UUID;
  v_high UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF p_to_user_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_TARGET' USING ERRCODE = 'P0001';
  END IF;

  IF p_to_user_id = v_uid THEN
    RAISE EXCEPTION 'CANNOT_ACTION_SELF' USING ERRCODE = 'P0001';
  END IF;

  IF v_action NOT IN ('like', 'skip') THEN
    RAISE EXCEPTION 'INVALID_ACTION' USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_to_user_id) THEN
    RAISE EXCEPTION 'PROFILE_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.dating_actions (from_user_id, to_user_id, action)
  VALUES (v_uid, p_to_user_id, v_action)
  ON CONFLICT (from_user_id, to_user_id) DO NOTHING
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    SELECT * INTO v_row
    FROM public.dating_actions
    WHERE from_user_id = v_uid AND to_user_id = p_to_user_id;
  END IF;

  IF v_action = 'like' THEN
    IF EXISTS (
      SELECT 1
      FROM public.dating_actions
      WHERE from_user_id = p_to_user_id
        AND to_user_id = v_uid
        AND action = 'like'
    ) THEN
      IF v_uid < p_to_user_id THEN
        v_low := v_uid;
        v_high := p_to_user_id;
      ELSE
        v_low := p_to_user_id;
        v_high := v_uid;
      END IF;

      INSERT INTO public.dating_matches (user_low, user_high)
      VALUES (v_low, v_high)
      ON CONFLICT (user_low, user_high) DO NOTHING;

      v_matched := TRUE;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'id', v_row.id,
    'from_user_id', v_row.from_user_id,
    'to_user_id', v_row.to_user_id,
    'action', v_row.action,
    'created_at', v_row.created_at,
    'matched', v_matched
  );
END;
$$;

REVOKE ALL ON FUNCTION public.dating_record_action(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dating_record_action(UUID, TEXT) TO authenticated;

-- Feed: candidates with avatar + gallery photos (max 5 urls total).
CREATE OR REPLACE FUNCTION public.dating_fetch_candidates(
  p_limit INTEGER DEFAULT 20
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_limit INTEGER := GREATEST(1, LEAST(COALESCE(p_limit, 20), 50));
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
          AND NOT EXISTS (
            SELECT 1
            FROM public.dating_actions da
            WHERE da.from_user_id = v_uid
              AND da.to_user_id = p.id
          )
          AND NOT EXISTS (
            SELECT 1
            FROM public.dating_matches dm
            WHERE (dm.user_low = v_uid AND dm.user_high = p.id)
               OR (dm.user_high = v_uid AND dm.user_low = p.id)
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

REVOKE ALL ON FUNCTION public.dating_fetch_candidates(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dating_fetch_candidates(INTEGER) TO authenticated;

COMMENT ON TABLE public.dating_actions IS
  'Like/skip actions for Знакомства. Users may only insert/select their own rows.';

COMMENT ON TABLE public.dating_matches IS
  'Mutual likes scaffold; readable by participants, written by dating_record_action.';
