-- ============================================================
-- Dating chats folder: type=dating, reports, block RPCs, city filter
-- ============================================================

-- ---------- conversations: dating type + dating_match_id ----------
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS dating_match_id UUID
    REFERENCES public.dating_matches (id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS conversations_dating_match_unique_idx
  ON public.conversations (dating_match_id)
  WHERE dating_match_id IS NOT NULL;

ALTER TABLE public.conversations DROP CONSTRAINT IF EXISTS conversations_type_check;
ALTER TABLE public.conversations
  ADD CONSTRAINT conversations_type_check
  CHECK (type IN ('market', 'clan', 'user', 'city', 'dating'));

ALTER TABLE public.conversations DROP CONSTRAINT IF EXISTS conversations_type_fields_chk;
ALTER TABLE public.conversations
  ADD CONSTRAINT conversations_type_fields_chk
  CHECK (
    (
      type = 'market'
      AND listing_id IS NOT NULL
      AND clan_id IS NULL
      AND city_name IS NULL
      AND dating_match_id IS NULL
    )
    OR (
      type = 'clan'
      AND clan_id IS NOT NULL
      AND listing_id IS NULL
      AND city_name IS NULL
      AND dating_match_id IS NULL
    )
    OR (
      type = 'user'
      AND listing_id IS NULL
      AND clan_id IS NULL
      AND city_name IS NULL
      AND dating_match_id IS NULL
    )
    OR (
      type = 'city'
      AND city_name IS NOT NULL
      AND listing_id IS NULL
      AND clan_id IS NULL
      AND clan_channel IS NULL
      AND dating_match_id IS NULL
    )
    OR (
      type = 'dating'
      AND listing_id IS NULL
      AND clan_id IS NULL
      AND city_name IS NULL
      AND clan_channel IS NULL
    )
  );

-- Migrate existing match-linked DMs from user → dating
UPDATE public.conversations c
SET
  type = 'dating',
  dating_match_id = dm.id
FROM public.dating_matches dm
WHERE dm.conversation_id = c.id
  AND c.type = 'user';

-- ---------- user_reports ----------
CREATE TABLE IF NOT EXISTS public.user_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  target_user_id UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  reason TEXT NOT NULL,
  description TEXT,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'reviewed', 'resolved')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT user_reports_no_self CHECK (reporter_id <> target_user_id)
);

CREATE INDEX IF NOT EXISTS user_reports_reporter_idx
  ON public.user_reports (reporter_id, created_at DESC);

CREATE INDEX IF NOT EXISTS user_reports_target_idx
  ON public.user_reports (target_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS user_reports_status_idx
  ON public.user_reports (status, created_at DESC);

ALTER TABLE public.user_reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "User reports insert own" ON public.user_reports;
CREATE POLICY "User reports insert own"
  ON public.user_reports
  FOR INSERT
  TO authenticated
  WITH CHECK (reporter_id = auth.uid());

DROP POLICY IF EXISTS "User reports select own" ON public.user_reports;
CREATE POLICY "User reports select own"
  ON public.user_reports
  FOR SELECT
  TO authenticated
  USING (reporter_id = auth.uid());

-- ---------- block / report RPCs ----------
CREATE OR REPLACE FUNCTION public.block_user(p_blocked_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_user1 UUID;
  v_user2 UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF p_blocked_user_id IS NULL OR p_blocked_user_id = v_uid THEN
    RAISE EXCEPTION 'INVALID_TARGET' USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_blocked_user_id) THEN
    RAISE EXCEPTION 'PROFILE_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.user_blocks (user_id, blocked_user_id)
  VALUES (v_uid, p_blocked_user_id)
  ON CONFLICT (user_id, blocked_user_id) DO NOTHING;

  -- Hide match from both sides by removing match row (keeps conversation history,
  -- but send_chat_message will reject further messages via block check).
  IF v_uid < p_blocked_user_id THEN
    v_user1 := v_uid;
    v_user2 := p_blocked_user_id;
  ELSE
    v_user1 := p_blocked_user_id;
    v_user2 := v_uid;
  END IF;

  DELETE FROM public.dating_matches
  WHERE user1_id = v_user1 AND user2_id = v_user2;
END;
$$;

REVOKE ALL ON FUNCTION public.block_user(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.block_user(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.report_user(
  p_target_user_id UUID,
  p_reason TEXT,
  p_description TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_reason TEXT := btrim(COALESCE(p_reason, ''));
  v_desc TEXT := NULLIF(btrim(COALESCE(p_description, '')), '');
  v_id UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF p_target_user_id IS NULL OR p_target_user_id = v_uid THEN
    RAISE EXCEPTION 'INVALID_TARGET' USING ERRCODE = 'P0001';
  END IF;

  IF char_length(v_reason) < 2 OR char_length(v_reason) > 120 THEN
    RAISE EXCEPTION 'INVALID_REASON' USING ERRCODE = 'P0001';
  END IF;

  IF v_desc IS NOT NULL AND char_length(v_desc) > 2000 THEN
    RAISE EXCEPTION 'INVALID_DESCRIPTION' USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_target_user_id) THEN
    RAISE EXCEPTION 'PROFILE_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.user_reports (
    reporter_id, target_user_id, reason, description, status
  )
  VALUES (v_uid, p_target_user_id, v_reason, v_desc, 'pending')
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.report_user(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.report_user(UUID, TEXT, TEXT) TO authenticated;

-- ---------- dating chat ensure (type=dating, idempotent) ----------
CREATE OR REPLACE FUNCTION public.dating_ensure_dating_chat(
  p_user_a UUID,
  p_user_b UUID,
  p_match_id UUID DEFAULT NULL
)
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

  PERFORM pg_advisory_xact_lock(hashtext('dating:' || v_a::text || ':' || v_b::text));

  IF p_match_id IS NOT NULL THEN
    SELECT conversation_id INTO v_conv
    FROM public.dating_matches
    WHERE id = p_match_id;

    IF v_conv IS NOT NULL THEN
      UPDATE public.conversations
      SET type = 'dating', dating_match_id = COALESCE(dating_match_id, p_match_id)
      WHERE id = v_conv;
      RETURN v_conv;
    END IF;

    SELECT id INTO v_conv
    FROM public.conversations
    WHERE dating_match_id = p_match_id
    LIMIT 1;

    IF v_conv IS NOT NULL THEN
      RETURN v_conv;
    END IF;
  END IF;

  SELECT c.id INTO v_conv
  FROM public.conversations c
  WHERE c.type = 'dating'
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
    IF p_match_id IS NOT NULL THEN
      UPDATE public.conversations
      SET dating_match_id = COALESCE(dating_match_id, p_match_id)
      WHERE id = v_conv;
    END IF;
    RETURN v_conv;
  END IF;

  SELECT nickname INTO v_title FROM public.profiles WHERE id = v_b;

  INSERT INTO public.conversations (type, title, dating_match_id)
  VALUES ('dating', COALESCE(v_title, 'Знакомства'), p_match_id)
  RETURNING id INTO v_conv;

  INSERT INTO public.conversation_members (conversation_id, user_id, role, last_read_at)
  VALUES
    (v_conv, v_a, 'member', NOW()),
    (v_conv, v_b, 'member', NOW());

  RETURN v_conv;
END;
$$;

REVOKE ALL ON FUNCTION public.dating_ensure_dating_chat(UUID, UUID, UUID) FROM PUBLIC;

-- Keep old helper name as wrapper for any callers
CREATE OR REPLACE FUNCTION public.dating_ensure_dm(p_user_a UUID, p_user_b UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.dating_ensure_dating_chat(p_user_a, p_user_b, NULL);
END;
$$;

REVOKE ALL ON FUNCTION public.dating_ensure_dm(UUID, UUID) FROM PUBLIC;

-- Restore personal DM helper (type=user) used by open_user_chat
CREATE OR REPLACE FUNCTION public.ensure_user_dm(p_other_user_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_nick TEXT;
  v_conv UUID;
  v_a UUID;
  v_b UUID;
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

  IF v_uid < p_other_user_id THEN
    v_a := v_uid;
    v_b := p_other_user_id;
  ELSE
    v_a := p_other_user_id;
    v_b := v_uid;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_a::text || ':' || v_b::text));

  SELECT nickname INTO v_nick FROM public.profiles WHERE id = p_other_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  SELECT c.id INTO v_conv
  FROM public.conversations c
  WHERE c.type = 'user'
    AND EXISTS (
      SELECT 1 FROM public.conversation_members m1
      WHERE m1.conversation_id = c.id AND m1.user_id = v_uid
    )
    AND EXISTS (
      SELECT 1 FROM public.conversation_members m2
      WHERE m2.conversation_id = c.id AND m2.user_id = p_other_user_id
    )
    AND (
      SELECT COUNT(*) FROM public.conversation_members mx
      WHERE mx.conversation_id = c.id
    ) = 2
  LIMIT 1;

  IF v_conv IS NOT NULL THEN
    RETURN v_conv;
  END IF;

  INSERT INTO public.conversations (type, title)
  VALUES ('user', v_nick)
  RETURNING id INTO v_conv;

  INSERT INTO public.conversation_members (conversation_id, user_id, role, last_read_at)
  VALUES
    (v_conv, v_uid, 'member', NOW()),
    (v_conv, p_other_user_id, 'member', NULL);

  RETURN v_conv;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_user_dm(UUID) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.open_user_chat(p_other_user_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.ensure_user_dm(p_other_user_id);
END;
$$;

REVOKE ALL ON FUNCTION public.open_user_chat(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.open_user_chat(UUID) TO authenticated;

-- ---------- process_dating_action: create dating conversation ----------
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
        INSERT INTO public.dating_matches (user1_id, user2_id)
        VALUES (v_user1, v_user2)
        ON CONFLICT (user1_id, user2_id) DO NOTHING
        RETURNING * INTO v_match;

        IF v_match.id IS NULL THEN
          SELECT * INTO v_match
          FROM public.dating_matches
          WHERE user1_id = v_user1 AND user2_id = v_user2;
        END IF;

        v_conv := public.dating_ensure_dating_chat(v_uid, target_user_id, v_match.id);

        UPDATE public.dating_matches
        SET conversation_id = v_conv
        WHERE id = v_match.id
        RETURNING * INTO v_match;

        UPDATE public.conversations
        SET dating_match_id = v_match.id, type = 'dating'
        WHERE id = v_conv;

        INSERT INTO public.dating_match_notifications (match_id, user_id)
        VALUES (v_match.id, target_user_id)
        ON CONFLICT (match_id, user_id) DO NOTHING;
      ELSE
        IF v_match.conversation_id IS NULL THEN
          v_conv := public.dating_ensure_dating_chat(v_uid, target_user_id, v_match.id);
          UPDATE public.dating_matches
          SET conversation_id = v_conv
          WHERE id = v_match.id
          RETURNING * INTO v_match;
        ELSE
          v_conv := v_match.conversation_id;
          UPDATE public.conversations
          SET type = 'dating', dating_match_id = COALESCE(dating_match_id, v_match.id)
          WHERE id = v_conv;
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
    'conversation_id', COALESCE(v_match.conversation_id, v_conv),
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

-- ---------- feed with optional city filter ----------
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

-- Drop old single-arg overload if present to avoid ambiguity
DROP FUNCTION IF EXISTS public.dating_fetch_candidates(INTEGER);

-- ---------- unread by folder including dating + city ----------
CREATE OR REPLACE FUNCTION public.conversation_unread_by_type()
RETURNS TABLE (
  type TEXT,
  unread_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH unread AS (
    SELECT c.type, COUNT(*)::BIGINT AS unread_count
    FROM public.messages m
    JOIN public.conversations c ON c.id = m.conversation_id
    JOIN public.conversation_members cm
      ON cm.conversation_id = c.id AND cm.user_id = auth.uid()
    WHERE m.sender_id <> auth.uid()
      AND m.deleted_at IS NULL
      AND (cm.last_read_at IS NULL OR m.created_at > cm.last_read_at)
    GROUP BY c.type
  )
  SELECT t.type, COALESCE(u.unread_count, 0)::BIGINT
  FROM (
    VALUES ('market'), ('clan'), ('user'), ('city'), ('dating')
  ) AS t(type)
  LEFT JOIN unread u ON u.type = t.type;
$$;

REVOKE ALL ON FUNCTION public.conversation_unread_by_type() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.conversation_unread_by_type() TO authenticated;

-- ---------- send_chat_message: block for dating + user DMs ----------
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

  IF v_conv_type IN ('user', 'dating', 'market') THEN
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

-- Hide blocked peers from get_my_matches (already filtered) — refresh get_my_matches
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

COMMENT ON COLUMN public.conversations.dating_match_id IS
  'Link to dating_matches for type=dating conversations.';
COMMENT ON TABLE public.user_reports IS
  'User reports from dating/chat; status for future admin review.';
