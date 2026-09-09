-- ============================================================
-- Hide dialog for me + image messages in chat
-- ============================================================

ALTER TABLE public.conversation_members
  ADD COLUMN IF NOT EXISTS hidden_at TIMESTAMPTZ;

-- ---------- Hide conversation (soft, current user only) ----------
CREATE OR REPLACE FUNCTION public.hide_conversation(p_conversation_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_type TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF p_conversation_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_CONVERSATION' USING ERRCODE = 'P0001';
  END IF;

  SELECT c.type INTO v_type
  FROM public.conversations c
  WHERE c.id = p_conversation_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'CONVERSATION_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_type NOT IN ('user', 'market', 'dating') THEN
    RAISE EXCEPTION 'CANNOT_HIDE_CONVERSATION' USING ERRCODE = 'P0001';
  END IF;

  IF NOT public.is_conversation_member(p_conversation_id) THEN
    RAISE EXCEPTION 'NOT_MEMBER' USING ERRCODE = '42501';
  END IF;

  UPDATE public.conversation_members
  SET hidden_at = NOW()
  WHERE conversation_id = p_conversation_id
    AND user_id = v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.hide_conversation(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hide_conversation(UUID) TO authenticated;

-- Unread ignores hidden dialogs
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
      AND cm.hidden_at IS NULL
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

-- ---------- Image column + constraints ----------
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS image_url TEXT;

ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_message_type_check;
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_voice_payload_chk;
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_payload_chk;

ALTER TABLE public.messages
  ADD CONSTRAINT messages_message_type_check
  CHECK (message_type IN ('text', 'voice', 'image'));

ALTER TABLE public.messages
  ADD CONSTRAINT messages_payload_chk
  CHECK (
    (
      message_type = 'text'
      AND char_length(trim(text)) > 0
      AND char_length(text) <= 4000
      AND audio_url IS NULL
      AND image_url IS NULL
    )
    OR (
      message_type = 'voice'
      AND audio_url IS NOT NULL
      AND char_length(trim(audio_url)) > 0
      AND image_url IS NULL
      AND (
        audio_duration_ms IS NULL
        OR (audio_duration_ms >= 500 AND audio_duration_ms <= 120000)
      )
    )
    OR (
      message_type = 'image'
      AND image_url IS NOT NULL
      AND char_length(trim(image_url)) > 0
      AND audio_url IS NULL
    )
  );

-- Storage bucket for chat images
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'chat-images',
  'chat-images',
  true,
  8388608,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE
SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Chat images publicly readable" ON storage.objects;
CREATE POLICY "Chat images publicly readable"
  ON storage.objects
  FOR SELECT
  USING (bucket_id = 'chat-images');

DROP POLICY IF EXISTS "Users upload chat images" ON storage.objects;
CREATE POLICY "Users upload chat images"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'chat-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "Users update chat images" ON storage.objects;
CREATE POLICY "Users update chat images"
  ON storage.objects
  FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'chat-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  )
  WITH CHECK (
    bucket_id = 'chat-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "Users delete chat images" ON storage.objects;
CREATE POLICY "Users delete chat images"
  ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'chat-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------- send_chat_message: image + unhide ----------
DROP FUNCTION IF EXISTS public.send_chat_message(UUID, TEXT, TEXT, TEXT, INTEGER);
DROP FUNCTION IF EXISTS public.send_chat_message(UUID, TEXT, TEXT, TEXT, INTEGER, TEXT);

CREATE OR REPLACE FUNCTION public.send_chat_message(
  p_conversation_id UUID,
  p_text TEXT DEFAULT NULL,
  p_message_type TEXT DEFAULT 'text',
  p_audio_url TEXT DEFAULT NULL,
  p_audio_duration_ms INTEGER DEFAULT NULL,
  p_image_url TEXT DEFAULT NULL
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
  v_image TEXT := NULLIF(trim(p_image_url), '');
  v_recent INTEGER;
  v_row public.messages;
  v_other UUID;
  v_conv_type TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF v_type NOT IN ('text', 'voice', 'image') THEN
    RAISE EXCEPTION 'INVALID_MESSAGE_TYPE' USING ERRCODE = 'P0001';
  END IF;

  IF NOT public.is_conversation_member(p_conversation_id) THEN
    RAISE EXCEPTION 'NOT_MEMBER' USING ERRCODE = '42501';
  END IF;

  IF public.is_chat_muted(p_conversation_id, v_uid) THEN
    RAISE EXCEPTION 'CHAT_MUTED' USING ERRCODE = 'P0001';
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
    v_image := NULL;
  ELSIF v_type = 'voice' THEN
    IF v_audio IS NULL THEN
      RAISE EXCEPTION 'EMPTY_AUDIO' USING ERRCODE = 'P0001';
    END IF;
    IF p_audio_duration_ms IS NOT NULL
       AND (p_audio_duration_ms < 500 OR p_audio_duration_ms > 120000) THEN
      RAISE EXCEPTION 'INVALID_AUDIO_DURATION' USING ERRCODE = 'P0001';
    END IF;
    v_text := '';
    v_image := NULL;
  ELSE
    IF v_image IS NULL THEN
      RAISE EXCEPTION 'EMPTY_IMAGE' USING ERRCODE = 'P0001';
    END IF;
    v_text := '';
    v_audio := NULL;
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
    audio_duration_ms,
    image_url
  )
  VALUES (
    p_conversation_id,
    v_uid,
    v_text,
    v_type,
    v_audio,
    CASE WHEN v_type = 'voice' THEN p_audio_duration_ms ELSE NULL END,
    v_image
  )
  RETURNING * INTO v_row;

  UPDATE public.conversations
  SET updated_at = NOW()
  WHERE id = p_conversation_id;

  UPDATE public.conversation_members
  SET last_read_at = NOW(),
      hidden_at = NULL
  WHERE conversation_id = p_conversation_id
    AND user_id = v_uid;

  -- Peer sees the dialog again when someone writes
  UPDATE public.conversation_members
  SET hidden_at = NULL
  WHERE conversation_id = p_conversation_id
    AND user_id <> v_uid
    AND hidden_at IS NOT NULL;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.send_chat_message(UUID, TEXT, TEXT, TEXT, INTEGER, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.send_chat_message(UUID, TEXT, TEXT, TEXT, INTEGER, TEXT) TO authenticated;

-- ---------- Unhide when reopening DMs / market ----------
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
    UPDATE public.conversation_members
    SET hidden_at = NULL
    WHERE conversation_id = v_conv
      AND user_id = v_uid
      AND hidden_at IS NOT NULL;
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
GRANT EXECUTE ON FUNCTION public.ensure_user_dm(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.open_market_chat(p_listing_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_seller UUID;
  v_title TEXT;
  v_conv UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT seller_id, title INTO v_seller, v_title
  FROM public.listings
  WHERE id = p_listing_id AND status = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'LISTING_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_seller = v_uid THEN
    RAISE EXCEPTION 'CANNOT_CHAT_SELF' USING ERRCODE = 'P0001';
  END IF;

  SELECT c.id INTO v_conv
  FROM public.conversations c
  JOIN public.conversation_members cm ON cm.conversation_id = c.id
  WHERE c.type = 'market'
    AND c.listing_id = p_listing_id
    AND cm.user_id = v_uid
  LIMIT 1;

  IF v_conv IS NOT NULL THEN
    UPDATE public.conversation_members
    SET hidden_at = NULL
    WHERE conversation_id = v_conv
      AND user_id = v_uid
      AND hidden_at IS NOT NULL;
    RETURN v_conv;
  END IF;

  INSERT INTO public.conversations (type, title, listing_id)
  VALUES ('market', v_title, p_listing_id)
  RETURNING id INTO v_conv;

  INSERT INTO public.conversation_members (conversation_id, user_id, role, last_read_at)
  VALUES
    (v_conv, v_uid, 'member', NOW()),
    (v_conv, v_seller, 'member', NULL)
  ON CONFLICT DO NOTHING;

  RETURN v_conv;
END;
$$;

REVOKE ALL ON FUNCTION public.open_market_chat(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.open_market_chat(UUID) TO authenticated;

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
  v_caller UUID := auth.uid();
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
      IF v_caller IS NOT NULL THEN
        UPDATE public.conversation_members
        SET hidden_at = NULL
        WHERE conversation_id = v_conv
          AND user_id = v_caller
          AND hidden_at IS NOT NULL;
      END IF;
      RETURN v_conv;
    END IF;

    SELECT id INTO v_conv
    FROM public.conversations
    WHERE dating_match_id = p_match_id
    LIMIT 1;

    IF v_conv IS NOT NULL THEN
      IF v_caller IS NOT NULL THEN
        UPDATE public.conversation_members
        SET hidden_at = NULL
        WHERE conversation_id = v_conv
          AND user_id = v_caller
          AND hidden_at IS NOT NULL;
      END IF;
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
    IF v_caller IS NOT NULL THEN
      UPDATE public.conversation_members
      SET hidden_at = NULL
      WHERE conversation_id = v_conv
        AND user_id = v_caller
        AND hidden_at IS NOT NULL;
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
GRANT EXECUTE ON FUNCTION public.dating_ensure_dating_chat(UUID, UUID, UUID) TO authenticated;
