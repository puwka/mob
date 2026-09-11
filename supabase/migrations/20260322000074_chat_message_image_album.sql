-- ============================================================
-- Chat image albums (up to 10 photos per message)
-- ============================================================

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS image_urls TEXT[] NOT NULL DEFAULT '{}';

-- Backfill from legacy single image_url
UPDATE public.messages
SET image_urls = ARRAY[image_url]
WHERE message_type = 'image'
  AND image_url IS NOT NULL
  AND char_length(trim(image_url)) > 0
  AND COALESCE(cardinality(image_urls), 0) = 0;

ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_payload_chk;

ALTER TABLE public.messages
  ADD CONSTRAINT messages_payload_chk
  CHECK (
    (
      message_type = 'text'
      AND char_length(trim(text)) > 0
      AND char_length(text) <= 4000
      AND audio_url IS NULL
      AND image_url IS NULL
      AND COALESCE(cardinality(image_urls), 0) = 0
    )
    OR (
      message_type = 'voice'
      AND audio_url IS NOT NULL
      AND char_length(trim(audio_url)) > 0
      AND image_url IS NULL
      AND COALESCE(cardinality(image_urls), 0) = 0
      AND (
        audio_duration_ms IS NULL
        OR (audio_duration_ms >= 500 AND audio_duration_ms <= 120000)
      )
    )
    OR (
      message_type = 'image'
      AND audio_url IS NULL
      AND (
        (
          image_url IS NOT NULL
          AND char_length(trim(image_url)) > 0
        )
        OR COALESCE(cardinality(image_urls), 0) > 0
      )
      AND COALESCE(cardinality(image_urls), 0) <= 10
    )
  );

DROP FUNCTION IF EXISTS public.send_chat_message(UUID, TEXT, TEXT, TEXT, INTEGER, TEXT, UUID);

CREATE OR REPLACE FUNCTION public.send_chat_message(
  p_conversation_id UUID,
  p_text TEXT DEFAULT NULL,
  p_message_type TEXT DEFAULT 'text',
  p_audio_url TEXT DEFAULT NULL,
  p_audio_duration_ms INTEGER DEFAULT NULL,
  p_image_url TEXT DEFAULT NULL,
  p_reply_to_message_id UUID DEFAULT NULL,
  p_image_urls TEXT[] DEFAULT NULL
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
  v_images TEXT[] := '{}';
  v_reply UUID := p_reply_to_message_id;
  v_recent INTEGER;
  v_row public.messages;
  v_other UUID;
  v_conv_type TEXT;
  v_clan_id UUID;
  v_clan_channel TEXT;
  v_clan_role TEXT;
  v_reply_conv UUID;
  v_url TEXT;
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

  SELECT c.type, c.clan_id, c.clan_channel
  INTO v_conv_type, v_clan_id, v_clan_channel
  FROM public.conversations c
  WHERE c.id = p_conversation_id;

  IF v_conv_type = 'clan' THEN
    IF v_clan_id IS NULL THEN
      RAISE EXCEPTION 'NOT_CLAN_MEMBER' USING ERRCODE = '42501';
    END IF;

    SELECT cm.role INTO v_clan_role
    FROM public.clan_members cm
    WHERE cm.clan_id = v_clan_id
      AND cm.user_id = v_uid;

    IF v_clan_role IS NULL THEN
      DELETE FROM public.conversation_members
      WHERE conversation_id = p_conversation_id
        AND user_id = v_uid;
      RAISE EXCEPTION 'NOT_CLAN_MEMBER' USING ERRCODE = '42501';
    END IF;

    IF v_clan_channel = 'officers'
       AND v_clan_role NOT IN ('leader', 'officer', 'trainer') THEN
      DELETE FROM public.conversation_members
      WHERE conversation_id = p_conversation_id
        AND user_id = v_uid;
      RAISE EXCEPTION 'NOT_CLAN_OFFICER' USING ERRCODE = '42501';
    END IF;
  END IF;

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

  IF v_reply IS NOT NULL THEN
    SELECT m.conversation_id INTO v_reply_conv
    FROM public.messages m
    WHERE m.id = v_reply;

    IF v_reply_conv IS NULL OR v_reply_conv <> p_conversation_id THEN
      RAISE EXCEPTION 'INVALID_REPLY_TARGET' USING ERRCODE = 'P0001';
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
    v_images := '{}';
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
    v_images := '{}';
  ELSE
    v_images := '{}';
    IF p_image_urls IS NOT NULL THEN
      FOREACH v_url IN ARRAY p_image_urls
      LOOP
        v_url := NULLIF(trim(v_url), '');
        IF v_url IS NOT NULL THEN
          v_images := array_append(v_images, v_url);
        END IF;
        EXIT WHEN cardinality(v_images) >= 10;
      END LOOP;
    END IF;

    IF cardinality(v_images) = 0 AND v_image IS NOT NULL THEN
      v_images := ARRAY[v_image];
    END IF;

    IF cardinality(v_images) = 0 THEN
      RAISE EXCEPTION 'EMPTY_IMAGE' USING ERRCODE = 'P0001';
    END IF;

    IF cardinality(v_images) > 10 THEN
      RAISE EXCEPTION 'TOO_MANY_IMAGES' USING ERRCODE = 'P0001';
    END IF;

    v_image := v_images[1];
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
    image_url,
    image_urls,
    reply_to_message_id
  )
  VALUES (
    p_conversation_id,
    v_uid,
    v_text,
    v_type,
    v_audio,
    CASE WHEN v_type = 'voice' THEN p_audio_duration_ms ELSE NULL END,
    v_image,
    v_images,
    v_reply
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

  UPDATE public.conversation_members
  SET hidden_at = NULL
  WHERE conversation_id = p_conversation_id
    AND user_id <> v_uid
    AND hidden_at IS NOT NULL;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.send_chat_message(UUID, TEXT, TEXT, TEXT, INTEGER, TEXT, UUID, TEXT[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.send_chat_message(UUID, TEXT, TEXT, TEXT, INTEGER, TEXT, UUID, TEXT[]) TO authenticated;
