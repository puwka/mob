-- ============================================================
-- Dating matches (full), blocks, process_dating_action, get_my_matches
-- ============================================================

-- ---------- user_blocks (architecture for block feature) ----------
CREATE TABLE IF NOT EXISTS public.user_blocks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  blocked_user_id UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT user_blocks_no_self CHECK (user_id <> blocked_user_id),
  CONSTRAINT user_blocks_unique_pair UNIQUE (user_id, blocked_user_id)
);

CREATE INDEX IF NOT EXISTS user_blocks_user_idx
  ON public.user_blocks (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS user_blocks_blocked_idx
  ON public.user_blocks (blocked_user_id);

ALTER TABLE public.user_blocks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "User blocks select own" ON public.user_blocks;
CREATE POLICY "User blocks select own"
  ON public.user_blocks
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "User blocks insert own" ON public.user_blocks;
CREATE POLICY "User blocks insert own"
  ON public.user_blocks
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "User blocks delete own" ON public.user_blocks;
CREATE POLICY "User blocks delete own"
  ON public.user_blocks
  FOR DELETE
  TO authenticated
  USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.is_users_blocked(p_a UUID, p_b UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_blocks ub
    WHERE (ub.user_id = p_a AND ub.blocked_user_id = p_b)
       OR (ub.user_id = p_b AND ub.blocked_user_id = p_a)
  );
$$;

REVOKE ALL ON FUNCTION public.is_users_blocked(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_users_blocked(UUID, UUID) TO authenticated;

-- ---------- dating_matches: normalize to user1/user2 + conversation ----------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'dating_matches'
      AND column_name = 'user_low'
  ) THEN
    ALTER TABLE public.dating_matches RENAME COLUMN user_low TO user1_id;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'dating_matches'
      AND column_name = 'user_high'
  ) THEN
    ALTER TABLE public.dating_matches RENAME COLUMN user_high TO user2_id;
  END IF;
END $$;

ALTER TABLE public.dating_matches
  ADD COLUMN IF NOT EXISTS conversation_id UUID
    REFERENCES public.conversations (id) ON DELETE SET NULL;

-- Recreate ordered + unique constraints under expected names
ALTER TABLE public.dating_matches
  DROP CONSTRAINT IF EXISTS dating_matches_ordered;
ALTER TABLE public.dating_matches
  DROP CONSTRAINT IF EXISTS dating_matches_unique_pair;
ALTER TABLE public.dating_matches
  DROP CONSTRAINT IF EXISTS dating_matches_user1_user2_order;
ALTER TABLE public.dating_matches
  DROP CONSTRAINT IF EXISTS dating_matches_user1_user2_unique;

ALTER TABLE public.dating_matches
  ADD CONSTRAINT dating_matches_user1_user2_order
    CHECK (user1_id < user2_id);

ALTER TABLE public.dating_matches
  ADD CONSTRAINT dating_matches_user1_user2_unique
    UNIQUE (user1_id, user2_id);

CREATE INDEX IF NOT EXISTS dating_matches_user1_idx
  ON public.dating_matches (user1_id, created_at DESC);

CREATE INDEX IF NOT EXISTS dating_matches_user2_idx
  ON public.dating_matches (user2_id, created_at DESC);

CREATE INDEX IF NOT EXISTS dating_matches_conversation_idx
  ON public.dating_matches (conversation_id);

DROP POLICY IF EXISTS "Dating matches select own" ON public.dating_matches;
CREATE POLICY "Dating matches select own"
  ON public.dating_matches
  FOR SELECT
  TO authenticated
  USING (user1_id = auth.uid() OR user2_id = auth.uid());

-- Pending in-app match alerts (both participants)
CREATE TABLE IF NOT EXISTS public.dating_match_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id UUID NOT NULL REFERENCES public.dating_matches (id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  seen_at TIMESTAMPTZ,
  CONSTRAINT dating_match_notifications_unique UNIQUE (match_id, user_id)
);

CREATE INDEX IF NOT EXISTS dating_match_notifications_user_unseen_idx
  ON public.dating_match_notifications (user_id, created_at DESC)
  WHERE seen_at IS NULL;

ALTER TABLE public.dating_match_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Dating match notifications select own"
  ON public.dating_match_notifications;
CREATE POLICY "Dating match notifications select own"
  ON public.dating_match_notifications
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Dating match notifications update own"
  ON public.dating_match_notifications;
CREATE POLICY "Dating match notifications update own"
  ON public.dating_match_notifications
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Ensure DM for a pair (SECURITY DEFINER; does not rely on auth.uid for membership)
CREATE OR REPLACE FUNCTION public.dating_ensure_dm(p_user_a UUID, p_user_b UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_a UUID;
  v_b UUID;
  v_conv UUID;
  v_title TEXT;
BEGIN
  IF p_user_a IS NULL OR p_user_b IS NULL OR p_user_a = p_user_b THEN
    RAISE EXCEPTION 'INVALID_DM_PAIR' USING ERRCODE = 'P0001';
  END IF;

  IF p_user_a < p_user_b THEN
    v_a := p_user_a;
    v_b := p_user_b;
  ELSE
    v_a := p_user_b;
    v_b := p_user_a;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_a::text || ':' || v_b::text));

  SELECT c.id INTO v_conv
  FROM public.conversations c
  WHERE c.type = 'user'
    AND EXISTS (
      SELECT 1 FROM public.conversation_members m1
      WHERE m1.conversation_id = c.id AND m1.user_id = v_a
    )
    AND EXISTS (
      SELECT 1 FROM public.conversation_members m2
      WHERE m2.conversation_id = c.id AND m2.user_id = v_b
    )
    AND (
      SELECT COUNT(*) FROM public.conversation_members mx
      WHERE mx.conversation_id = c.id
    ) = 2
  LIMIT 1;

  IF v_conv IS NOT NULL THEN
    RETURN v_conv;
  END IF;

  SELECT nickname INTO v_title FROM public.profiles WHERE id = v_b;

  INSERT INTO public.conversations (type, title)
  VALUES ('user', COALESCE(v_title, 'Чат'))
  RETURNING id INTO v_conv;

  INSERT INTO public.conversation_members (conversation_id, user_id, role, last_read_at)
  VALUES
    (v_conv, v_a, 'member', NOW()),
    (v_conv, v_b, 'member', NOW());

  RETURN v_conv;
END;
$$;

REVOKE ALL ON FUNCTION public.dating_ensure_dm(UUID, UUID) FROM PUBLIC;

-- ---------- process_dating_action (canonical) ----------
CREATE OR REPLACE FUNCTION public.process_dating_action(
  target_user_id UUID,
  action TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_action TEXT := lower(btrim(COALESCE(action, '')));
  v_row public.dating_actions;
  v_matched BOOLEAN := FALSE;
  v_match public.dating_matches;
  v_user1 UUID;
  v_user2 UUID;
  v_conv UUID;
  v_me public.profiles;
  v_other public.profiles;
  v_inserted BOOLEAN := FALSE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF target_user_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_TARGET' USING ERRCODE = 'P0001';
  END IF;

  IF target_user_id = v_uid THEN
    RAISE EXCEPTION 'CANNOT_ACTION_SELF' USING ERRCODE = 'P0001';
  END IF;

  IF v_action NOT IN ('like', 'skip') THEN
    RAISE EXCEPTION 'INVALID_ACTION' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_other FROM public.profiles WHERE id = target_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROFILE_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_me FROM public.profiles WHERE id = v_uid;

  IF public.is_users_blocked(v_uid, target_user_id) THEN
    RAISE EXCEPTION 'USER_BLOCKED' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.dating_actions (from_user_id, to_user_id, action)
  VALUES (v_uid, target_user_id, v_action)
  ON CONFLICT (from_user_id, to_user_id) DO NOTHING
  RETURNING * INTO v_row;

  IF FOUND THEN
    v_inserted := TRUE;
  ELSE
    SELECT * INTO v_row
    FROM public.dating_actions
    WHERE from_user_id = v_uid AND to_user_id = target_user_id;
  END IF;

  -- Match only on a successful like when reciprocal like exists (never on skip).
  IF v_action = 'like'
     AND v_row.action = 'like'
     AND NOT public.is_users_blocked(v_uid, target_user_id)
  THEN
    IF EXISTS (
      SELECT 1
      FROM public.dating_actions
      WHERE from_user_id = target_user_id
        AND to_user_id = v_uid
        AND action = 'like'
    ) THEN
      IF v_uid < target_user_id THEN
        v_user1 := v_uid;
        v_user2 := target_user_id;
      ELSE
        v_user1 := target_user_id;
        v_user2 := v_uid;
      END IF;

      SELECT * INTO v_match
      FROM public.dating_matches
      WHERE user1_id = v_user1 AND user2_id = v_user2;

      IF NOT FOUND THEN
        v_conv := public.dating_ensure_dm(v_uid, target_user_id);

        INSERT INTO public.dating_matches (
          user1_id, user2_id, conversation_id
        )
        VALUES (v_user1, v_user2, v_conv)
        ON CONFLICT (user1_id, user2_id) DO NOTHING
        RETURNING * INTO v_match;

        IF v_match.id IS NULL THEN
          SELECT * INTO v_match
          FROM public.dating_matches
          WHERE user1_id = v_user1 AND user2_id = v_user2;
        END IF;

        IF v_match.conversation_id IS NULL AND v_conv IS NOT NULL THEN
          UPDATE public.dating_matches
          SET conversation_id = v_conv
          WHERE id = v_match.id
          RETURNING * INTO v_match;
        END IF;

        INSERT INTO public.dating_match_notifications (match_id, user_id)
        VALUES (v_match.id, target_user_id)
        ON CONFLICT (match_id, user_id) DO NOTHING;
      ELSE
        IF v_match.conversation_id IS NULL THEN
          v_conv := public.dating_ensure_dm(v_uid, target_user_id);
          UPDATE public.dating_matches
          SET conversation_id = v_conv
          WHERE id = v_match.id
          RETURNING * INTO v_match;
        END IF;
      END IF;

      v_matched := TRUE;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'action_id', v_row.id,
    'from_user_id', v_row.from_user_id,
    'to_user_id', v_row.to_user_id,
    'action', v_row.action,
    'created_at', v_row.created_at,
    'inserted', v_inserted,
    'matched', v_matched,
    'match_id', v_match.id,
    'conversation_id', v_match.conversation_id,
    'me', jsonb_build_object(
      'id', v_me.id,
      'nickname', v_me.nickname,
      'city', v_me.city,
      'avatar_url', v_me.avatar_url
    ),
    'target', jsonb_build_object(
      'id', v_other.id,
      'nickname', v_other.nickname,
      'city', v_other.city,
      'avatar_url', v_other.avatar_url
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.process_dating_action(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_dating_action(UUID, TEXT) TO authenticated;

-- Keep old name as thin wrapper for any early clients
CREATE OR REPLACE FUNCTION public.dating_record_action(
  p_to_user_id UUID,
  p_action TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.process_dating_action(p_to_user_id, p_action);
END;
$$;

REVOKE ALL ON FUNCTION public.dating_record_action(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dating_record_action(UUID, TEXT) TO authenticated;

-- ---------- get_my_matches ----------
CREATE OR REPLACE FUNCTION public.get_my_matches()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  RETURN COALESCE(
    (
      SELECT jsonb_agg(row_data ORDER BY sort_key DESC)
      FROM (
        SELECT
          jsonb_build_object(
            'match_id', dm.id,
            'created_at', dm.created_at,
            'conversation_id', dm.conversation_id,
            'user_id', p.id,
            'nickname', p.nickname,
            'city', p.city,
            'avatar_url', p.avatar_url
          ) AS row_data,
          dm.created_at AS sort_key
        FROM public.dating_matches dm
        JOIN public.profiles p
          ON p.id = CASE
            WHEN dm.user1_id = v_uid THEN dm.user2_id
            ELSE dm.user1_id
          END
        WHERE (dm.user1_id = v_uid OR dm.user2_id = v_uid)
          AND NOT public.is_users_blocked(v_uid, p.id)
        ORDER BY dm.created_at DESC
      ) matches
    ),
    '[]'::jsonb
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_matches() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_matches() TO authenticated;

-- ---------- pending match notifications ----------
CREATE OR REPLACE FUNCTION public.get_pending_dating_match_notifications()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  RETURN COALESCE(
    (
      SELECT jsonb_agg(row_data ORDER BY sort_key DESC)
      FROM (
        SELECT
          jsonb_build_object(
            'notification_id', n.id,
            'match_id', dm.id,
            'conversation_id', dm.conversation_id,
            'created_at', n.created_at,
            'me', jsonb_build_object(
              'id', me.id,
              'nickname', me.nickname,
              'city', me.city,
              'avatar_url', me.avatar_url
            ),
            'other', jsonb_build_object(
              'id', oth.id,
              'nickname', oth.nickname,
              'city', oth.city,
              'avatar_url', oth.avatar_url
            )
          ) AS row_data,
          n.created_at AS sort_key
        FROM public.dating_match_notifications n
        JOIN public.dating_matches dm ON dm.id = n.match_id
        JOIN public.profiles me ON me.id = v_uid
        JOIN public.profiles oth ON oth.id = CASE
          WHEN dm.user1_id = v_uid THEN dm.user2_id
          ELSE dm.user1_id
        END
        WHERE n.user_id = v_uid
          AND n.seen_at IS NULL
          AND NOT public.is_users_blocked(v_uid, oth.id)
        ORDER BY n.created_at DESC
        LIMIT 10
      ) rows
    ),
    '[]'::jsonb
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_pending_dating_match_notifications() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_pending_dating_match_notifications() TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_dating_match_notification_seen(
  p_notification_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  UPDATE public.dating_match_notifications
  SET seen_at = NOW()
  WHERE id = p_notification_id
    AND user_id = v_uid
    AND seen_at IS NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_dating_match_notification_seen(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_dating_match_notification_seen(UUID) TO authenticated;

-- ---------- feed: exclude blocks + new match columns ----------
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
          AND NOT public.is_users_blocked(v_uid, p.id)
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

REVOKE ALL ON FUNCTION public.dating_fetch_candidates(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dating_fetch_candidates(INTEGER) TO authenticated;

-- ---------- block messaging ----------
CREATE OR REPLACE FUNCTION public.open_user_chat(p_other_user_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF p_other_user_id = v_uid THEN
    RAISE EXCEPTION 'CANNOT_CHAT_SELF' USING ERRCODE = 'P0001';
  END IF;

  IF public.is_users_blocked(v_uid, p_other_user_id) THEN
    RAISE EXCEPTION 'USER_BLOCKED' USING ERRCODE = 'P0001';
  END IF;

  RETURN public.dating_ensure_dm(v_uid, p_other_user_id);
END;
$$;

REVOKE ALL ON FUNCTION public.open_user_chat(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.open_user_chat(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.send_chat_message(
  p_conversation_id UUID,
  p_text TEXT DEFAULT NULL,
  p_message_type TEXT DEFAULT 'text',
  p_audio_url TEXT DEFAULT NULL,
  p_audio_duration_ms INTEGER DEFAULT NULL
)
RETURNS public.messages
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_type TEXT := COALESCE(NULLIF(trim(p_message_type), ''), 'text');
  v_text TEXT := COALESCE(trim(p_text), '');
  v_audio TEXT := NULLIF(trim(p_audio_url), '');
  v_recent INTEGER;
  v_row public.messages;
  v_other UUID;
  v_conv_type TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF v_type NOT IN ('text', 'voice') THEN
    RAISE EXCEPTION 'INVALID_MESSAGE_TYPE' USING ERRCODE = 'P0001';
  END IF;

  IF NOT public.is_conversation_member(p_conversation_id) THEN
    RAISE EXCEPTION 'NOT_MEMBER' USING ERRCODE = '42501';
  END IF;

  SELECT c.type INTO v_conv_type
  FROM public.conversations c
  WHERE c.id = p_conversation_id;

  IF v_conv_type = 'user' THEN
    SELECT cm.user_id INTO v_other
    FROM public.conversation_members cm
    WHERE cm.conversation_id = p_conversation_id
      AND cm.user_id <> v_uid
    LIMIT 1;

    IF v_other IS NOT NULL AND public.is_users_blocked(v_uid, v_other) THEN
      RAISE EXCEPTION 'USER_BLOCKED' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  IF v_type = 'text' THEN
    IF v_text IS NULL OR char_length(v_text) = 0 THEN
      RAISE EXCEPTION 'EMPTY_MESSAGE' USING ERRCODE = 'P0001';
    END IF;
    IF char_length(v_text) > 4000 THEN
      RAISE EXCEPTION 'MESSAGE_TOO_LONG' USING ERRCODE = 'P0001';
    END IF;
    v_audio := NULL;
  ELSE
    IF v_audio IS NULL THEN
      RAISE EXCEPTION 'EMPTY_AUDIO' USING ERRCODE = 'P0001';
    END IF;
    IF p_audio_duration_ms IS NOT NULL
       AND (p_audio_duration_ms < 500 OR p_audio_duration_ms > 120000) THEN
      RAISE EXCEPTION 'INVALID_AUDIO_DURATION' USING ERRCODE = 'P0001';
    END IF;
    v_text := '';
  END IF;

  SELECT COUNT(*)::INTEGER INTO v_recent
  FROM public.messages
  WHERE sender_id = v_uid
    AND created_at > NOW() - INTERVAL '20 seconds';

  IF v_recent >= 8 THEN
    RAISE EXCEPTION 'FLOOD' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.messages (
    conversation_id,
    sender_id,
    text,
    message_type,
    audio_url,
    audio_duration_ms
  )
  VALUES (
    p_conversation_id,
    v_uid,
    v_text,
    v_type,
    v_audio,
    CASE WHEN v_type = 'voice' THEN p_audio_duration_ms ELSE NULL END
  )
  RETURNING * INTO v_row;

  UPDATE public.conversations
  SET updated_at = NOW()
  WHERE id = p_conversation_id;

  UPDATE public.conversation_members
  SET last_read_at = NOW()
  WHERE conversation_id = p_conversation_id AND user_id = v_uid;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.send_chat_message(UUID, TEXT, TEXT, TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.send_chat_message(UUID, TEXT, TEXT, TEXT, INTEGER) TO authenticated;

COMMENT ON TABLE public.dating_matches IS
  'Mutual likes; user1_id < user2_id; conversation_id for DM.';
COMMENT ON TABLE public.user_blocks IS
  'User block list; excludes from dating/match/DM messaging.';
COMMENT ON TABLE public.dating_match_notifications IS
  'In-app match alerts for both participants.';
