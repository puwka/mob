-- ============================================================
-- Voice messages in chat
-- ============================================================

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS message_type TEXT NOT NULL DEFAULT 'text',
  ADD COLUMN IF NOT EXISTS audio_url TEXT,
  ADD COLUMN IF NOT EXISTS audio_duration_ms INTEGER;

ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_text_check;
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_message_type_check;
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_voice_payload_chk;

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT con.conname
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
    WHERE nsp.nspname = 'public'
      AND rel.relname = 'messages'
      AND con.contype = 'c'
      AND pg_get_constraintdef(con.oid) ILIKE '%text%'
  LOOP
    EXECUTE format('ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS %I', r.conname);
  END LOOP;
END;
$$;

ALTER TABLE public.messages
  ALTER COLUMN text SET DEFAULT '';

ALTER TABLE public.messages
  ADD CONSTRAINT messages_message_type_check
  CHECK (message_type IN ('text', 'voice'));

ALTER TABLE public.messages
  ADD CONSTRAINT messages_voice_payload_chk
  CHECK (
    (
      message_type = 'text'
      AND char_length(trim(text)) > 0
      AND char_length(text) <= 4000
      AND audio_url IS NULL
    )
    OR (
      message_type = 'voice'
      AND audio_url IS NOT NULL
      AND char_length(trim(audio_url)) > 0
      AND (
        audio_duration_ms IS NULL
        OR (audio_duration_ms >= 500 AND audio_duration_ms <= 120000)
      )
    )
  );

-- Storage bucket
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'chat-voice',
  'chat-voice',
  true,
  5242880,
  ARRAY[
    'audio/mp4',
    'audio/m4a',
    'audio/aac',
    'audio/mpeg',
    'audio/webm',
    'audio/ogg',
    'audio/wav',
    'audio/x-m4a'
  ]
)
ON CONFLICT (id) DO UPDATE
SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Chat voice publicly readable" ON storage.objects;
CREATE POLICY "Chat voice publicly readable"
  ON storage.objects
  FOR SELECT
  USING (bucket_id = 'chat-voice');

DROP POLICY IF EXISTS "Users upload chat voice" ON storage.objects;
CREATE POLICY "Users upload chat voice"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'chat-voice'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "Users update chat voice" ON storage.objects;
CREATE POLICY "Users update chat voice"
  ON storage.objects
  FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'chat-voice'
    AND (storage.foldername(name))[1] = auth.uid()::text
  )
  WITH CHECK (
    bucket_id = 'chat-voice'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "Users delete chat voice" ON storage.objects;
CREATE POLICY "Users delete chat voice"
  ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'chat-voice'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP FUNCTION IF EXISTS public.send_chat_message(UUID, TEXT);

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

COMMENT ON COLUMN public.messages.message_type IS 'text | voice';
COMMENT ON COLUMN public.messages.audio_url IS 'Public URL in chat-voice bucket';
