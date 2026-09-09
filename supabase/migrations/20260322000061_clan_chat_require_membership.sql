-- Clan chat write access: require live clan_members (not only conversation_members).
-- Purge orphan conversation_members; harden open_clan_chat + send_chat_message.

-- One-shot: remove anyone not currently in the clan from clan chats
DELETE FROM public.conversation_members cm
USING public.conversations c
WHERE c.id = cm.conversation_id
  AND c.type = 'clan'
  AND NOT EXISTS (
    SELECT 1
    FROM public.clan_members m
    WHERE m.clan_id = c.clan_id
      AND m.user_id = cm.user_id
      AND (
        c.clan_channel = 'general'
        OR m.role IN ('leader', 'officer', 'trainer')
      )
  );

CREATE OR REPLACE FUNCTION public.open_clan_chat(p_clan_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_name TEXT;
  v_conv UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.clan_members
    WHERE clan_id = p_clan_id AND user_id = v_uid
  ) THEN
    RAISE EXCEPTION 'NOT_CLAN_MEMBER' USING ERRCODE = '42501';
  END IF;

  SELECT name INTO v_name FROM public.clans WHERE id = p_clan_id;

  SELECT id INTO v_conv
  FROM public.conversations
  WHERE type = 'clan'
    AND clan_id = p_clan_id
    AND clan_channel = 'general'
  LIMIT 1;

  IF v_conv IS NULL THEN
    INSERT INTO public.conversations (type, title, clan_id, clan_channel)
    VALUES ('clan', v_name, p_clan_id, 'general')
    RETURNING id INTO v_conv;
  ELSE
    UPDATE public.conversations
    SET title = COALESCE(v_name, title)
    WHERE id = v_conv;
  END IF;

  INSERT INTO public.conversation_members (conversation_id, user_id, role)
  SELECT v_conv, cm.user_id, 'member'
  FROM public.clan_members cm
  WHERE cm.clan_id = p_clan_id
  ON CONFLICT DO NOTHING;

  DELETE FROM public.conversation_members cm
  WHERE cm.conversation_id = v_conv
    AND NOT EXISTS (
      SELECT 1
      FROM public.clan_members m
      WHERE m.clan_id = p_clan_id
        AND m.user_id = cm.user_id
    );

  RETURN v_conv;
END;
$$;

REVOKE ALL ON FUNCTION public.open_clan_chat(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.open_clan_chat(UUID) TO authenticated;

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
  v_clan_id UUID;
  v_clan_channel TEXT;
  v_clan_role TEXT;
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

  -- Clan chats: must be an active clan member (join request is not enough)
  IF v_conv_type = 'clan' THEN
    IF v_clan_id IS NULL THEN
      RAISE EXCEPTION 'NOT_CLAN_MEMBER' USING ERRCODE = '42501';
    END IF;

    SELECT cm.role INTO v_clan_role
    FROM public.clan_members cm
    WHERE cm.clan_id = v_clan_id
      AND cm.user_id = v_uid;

    IF v_clan_role IS NULL THEN
      -- Drop stale chat membership so the dialog disappears from inbox
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
