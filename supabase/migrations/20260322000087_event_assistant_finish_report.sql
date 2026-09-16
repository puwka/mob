-- ============================================================
-- Event assistant, keep chat after finish (3 days), report
-- ============================================================

-- ---------- Schema ----------
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS assistant_user_id UUID REFERENCES public.profiles (id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS finished_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS report_winner TEXT
    CHECK (report_winner IS NULL OR report_winner IN ('light', 'dark', 'draw')),
  ADD COLUMN IF NOT EXISTS report_score_light INTEGER
    CHECK (report_score_light IS NULL OR report_score_light >= 0),
  ADD COLUMN IF NOT EXISTS report_score_dark INTEGER
    CHECK (report_score_dark IS NULL OR report_score_dark >= 0),
  ADD COLUMN IF NOT EXISTS report_submitted_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS events_assistant_user_id_idx
  ON public.events (assistant_user_id)
  WHERE assistant_user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS events_finished_at_idx
  ON public.events (finished_at DESC)
  WHERE finished_at IS NOT NULL;

-- Backfill finished_at for already finished events
UPDATE public.events
SET finished_at = COALESCE(updated_at, created_at, NOW())
WHERE status = 'finished'
  AND finished_at IS NULL;

-- ---------- Helpers ----------
CREATE OR REPLACE FUNCTION public.is_event_manager(p_event_id UUID, p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.events e
    WHERE e.id = p_event_id
      AND p_user_id IS NOT NULL
      AND (
        e.organizer_id = p_user_id
        OR e.assistant_user_id = p_user_id
        OR public.is_admin()
      )
  );
$$;

REVOKE ALL ON FUNCTION public.is_event_manager(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_event_manager(UUID, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.post_event_chat_message(
  p_event_id UUID,
  p_sender_id UUID,
  p_message_type TEXT,
  p_text TEXT,
  p_share_payload JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_conv UUID;
  v_id UUID;
BEGIN
  SELECT id INTO v_conv
  FROM public.conversations
  WHERE type = 'event' AND event_id = p_event_id
  LIMIT 1;

  IF v_conv IS NULL THEN
    RETURN NULL;
  END IF;

  -- Ensure sender is a member so FK/membership stays consistent
  INSERT INTO public.conversation_members (conversation_id, user_id, role, last_read_at)
  VALUES (v_conv, p_sender_id, 'member', NOW())
  ON CONFLICT (conversation_id, user_id) DO NOTHING;

  INSERT INTO public.messages (
    conversation_id,
    sender_id,
    text,
    message_type,
    share_ref_id,
    share_payload
  )
  VALUES (
    v_conv,
    p_sender_id,
    COALESCE(p_text, ''),
    p_message_type,
    p_event_id,
    p_share_payload
  )
  RETURNING id INTO v_id;

  UPDATE public.conversations
  SET updated_at = NOW()
  WHERE id = v_conv;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.post_event_chat_message(UUID, UUID, TEXT, TEXT, JSONB) FROM PUBLIC;
-- Only callable from other SECURITY DEFINER functions (finish/report)
REVOKE ALL ON FUNCTION public.post_event_chat_message(UUID, UUID, TEXT, TEXT, JSONB) FROM authenticated;

-- ---------- Message types: system + event_report ----------
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_message_type_check;
ALTER TABLE public.messages
  ADD CONSTRAINT messages_message_type_check
  CHECK (message_type IN (
    'text', 'voice', 'image', 'video',
    'listing', 'event', 'profile',
    'system', 'event_report'
  ));

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
      AND video_url IS NULL
      AND share_ref_id IS NULL
      AND share_payload IS NULL
    )
    OR (
      message_type = 'voice'
      AND audio_url IS NOT NULL
      AND char_length(trim(audio_url)) > 0
      AND image_url IS NULL
      AND COALESCE(cardinality(image_urls), 0) = 0
      AND video_url IS NULL
      AND share_ref_id IS NULL
      AND share_payload IS NULL
      AND (
        audio_duration_ms IS NULL
        OR (audio_duration_ms >= 500 AND audio_duration_ms <= 120000)
      )
    )
    OR (
      message_type = 'image'
      AND audio_url IS NULL
      AND video_url IS NULL
      AND share_ref_id IS NULL
      AND share_payload IS NULL
      AND (
        (
          image_url IS NOT NULL
          AND char_length(trim(image_url)) > 0
        )
        OR COALESCE(cardinality(image_urls), 0) > 0
      )
      AND COALESCE(cardinality(image_urls), 0) <= 10
    )
    OR (
      message_type = 'video'
      AND video_url IS NOT NULL
      AND char_length(trim(video_url)) > 0
      AND audio_url IS NULL
      AND image_url IS NULL
      AND COALESCE(cardinality(image_urls), 0) = 0
      AND share_ref_id IS NULL
      AND share_payload IS NULL
      AND (
        video_duration_ms IS NULL
        OR (video_duration_ms >= 500 AND video_duration_ms <= 180000)
      )
    )
    OR (
      message_type IN ('listing', 'event', 'profile')
      AND share_ref_id IS NOT NULL
      AND share_payload IS NOT NULL
      AND jsonb_typeof(share_payload) = 'object'
      AND char_length(COALESCE(share_payload->>'title', '')) > 0
      AND audio_url IS NULL
      AND image_url IS NULL
      AND COALESCE(cardinality(image_urls), 0) = 0
      AND video_url IS NULL
    )
    OR (
      message_type = 'system'
      AND char_length(trim(text)) > 0
      AND char_length(text) <= 4000
      AND audio_url IS NULL
      AND image_url IS NULL
      AND COALESCE(cardinality(image_urls), 0) = 0
      AND video_url IS NULL
    )
    OR (
      message_type = 'event_report'
      AND share_ref_id IS NOT NULL
      AND share_payload IS NOT NULL
      AND jsonb_typeof(share_payload) = 'object'
      AND char_length(COALESCE(share_payload->>'title', '')) > 0
      AND audio_url IS NULL
      AND image_url IS NULL
      AND COALESCE(cardinality(image_urls), 0) = 0
      AND video_url IS NULL
    )
  );

CREATE OR REPLACE FUNCTION public.trg_notify_on_chat_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_preview TEXT;
BEGIN
  IF NEW.deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  v_preview := CASE
    WHEN NEW.message_type = 'voice' THEN 'Голосовое сообщение'
    WHEN NEW.message_type = 'image' THEN 'Фото'
    WHEN NEW.message_type = 'video' THEN 'Видео'
    WHEN NEW.message_type = 'listing' THEN 'Объявление'
    WHEN NEW.message_type = 'event' THEN 'Мероприятие'
    WHEN NEW.message_type = 'profile' THEN 'Профиль'
    WHEN NEW.message_type = 'system' THEN COALESCE(NULLIF(btrim(NEW.text), ''), 'Системное сообщение')
    WHEN NEW.message_type = 'event_report' THEN 'Итоги игры'
    ELSE COALESCE(NULLIF(btrim(NEW.text), ''), 'Новое сообщение')
  END;

  PERFORM public.emit_chat_message_notification(
    NEW.conversation_id,
    NEW.sender_id,
    v_preview
  );
  RETURN NEW;
END;
$$;

-- ---------- Block non-manager writes in finished event chats ----------
CREATE OR REPLACE FUNCTION public.trg_block_finished_event_chat_write()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event_id UUID;
  v_status TEXT;
  v_org UUID;
  v_asst UUID;
BEGIN
  SELECT c.event_id INTO v_event_id
  FROM public.conversations c
  WHERE c.id = NEW.conversation_id;

  IF v_event_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT e.status, e.organizer_id, e.assistant_user_id
  INTO v_status, v_org, v_asst
  FROM public.events e
  WHERE e.id = v_event_id;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  IF v_status = 'cancelled' THEN
    RAISE EXCEPTION 'EVENT_CHAT_READONLY' USING ERRCODE = 'P0001';
  END IF;

  IF v_status = 'finished' THEN
    IF NEW.sender_id IS DISTINCT FROM v_org
       AND NEW.sender_id IS DISTINCT FROM v_asst
       AND NOT public.is_admin() THEN
      RAISE EXCEPTION 'EVENT_CHAT_READONLY' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS messages_block_finished_event_chat ON public.messages;
CREATE TRIGGER messages_block_finished_event_chat
  BEFORE INSERT ON public.messages
  FOR EACH ROW
  EXECUTE PROCEDURE public.trg_block_finished_event_chat_write();

-- ---------- ensure_event_chat: keep finished chats ----------
CREATE OR REPLACE FUNCTION public.ensure_event_chat(p_event_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event public.events%ROWTYPE;
  v_conv UUID;
BEGIN
  IF p_event_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_EVENT' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_event FROM public.events WHERE id = p_event_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_event.status = 'cancelled' THEN
    DELETE FROM public.conversations
    WHERE type = 'event' AND event_id = p_event_id;
    RETURN NULL;
  END IF;

  -- Hide chats after 3 days post-finish
  IF v_event.status = 'finished'
     AND v_event.finished_at IS NOT NULL
     AND v_event.finished_at < NOW() - INTERVAL '3 days' THEN
    DELETE FROM public.conversations
    WHERE type = 'event' AND event_id = p_event_id;
    RETURN NULL;
  END IF;

  SELECT id INTO v_conv
  FROM public.conversations
  WHERE type = 'event' AND event_id = p_event_id
  LIMIT 1;

  IF v_conv IS NULL THEN
    INSERT INTO public.conversations (type, title, event_id)
    VALUES ('event', v_event.title, p_event_id)
    RETURNING id INTO v_conv;
  ELSE
    UPDATE public.conversations
    SET title = v_event.title
    WHERE id = v_conv
      AND title IS DISTINCT FROM v_event.title;
  END IF;

  INSERT INTO public.conversation_members (conversation_id, user_id, role, last_read_at)
  VALUES (v_conv, v_event.organizer_id, 'owner', NOW())
  ON CONFLICT (conversation_id, user_id) DO NOTHING;

  IF v_event.assistant_user_id IS NOT NULL THEN
    INSERT INTO public.conversation_members (conversation_id, user_id, role, last_read_at)
    VALUES (v_conv, v_event.assistant_user_id, 'member', NOW())
    ON CONFLICT (conversation_id, user_id) DO NOTHING;
  END IF;

  RETURN v_conv;
END;
$$;

-- ---------- Trigger on status change: keep chat on finish ----------
CREATE OR REPLACE FUNCTION public.delete_event_conversation_on_end()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'cancelled'
     AND OLD.status IS DISTINCT FROM NEW.status THEN
    DELETE FROM public.conversations
    WHERE type = 'event' AND event_id = NEW.id;
  ELSIF NEW.status = 'finished'
        AND OLD.status IS DISTINCT FROM NEW.status THEN
    PERFORM public.ensure_event_chat(NEW.id);
  ELSIF NEW.status IN ('draft', 'active')
        AND OLD.status IN ('finished', 'cancelled')
        AND NEW.status IS DISTINCT FROM OLD.status THEN
    PERFORM public.ensure_event_chat(NEW.id);
  END IF;

  IF NEW.title IS DISTINCT FROM OLD.title THEN
    UPDATE public.conversations
    SET title = NEW.title
    WHERE type = 'event' AND event_id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;

-- ---------- finish_event ----------
CREATE OR REPLACE FUNCTION public.finish_event(p_event_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_event public.events%ROWTYPE;
  v_msg TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_event
  FROM public.events
  WHERE id = p_event_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF NOT public.is_event_manager(p_event_id, v_uid) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF v_event.status IN ('finished', 'cancelled') THEN
    RETURN;
  END IF;

  UPDATE public.events
  SET status = 'finished',
      finished_at = NOW(),
      updated_at = NOW()
  WHERE id = p_event_id
  RETURNING * INTO v_event;

  PERFORM public.ensure_event_chat(p_event_id);

  v_msg := 'Мероприятие «' || v_event.title || '» завершено. '
        || 'Чат доступен ещё 3 дня. Писать могут только организатор и помощник.';

  PERFORM public.post_event_chat_message(
    p_event_id,
    v_event.organizer_id,
    'system',
    v_msg,
    jsonb_build_object(
      'kind', 'event_finished',
      'title', v_event.title
    )
  );
END;
$$;

-- ---------- auto_finish_past_events ----------
CREATE OR REPLACE FUNCTION public.auto_finish_past_events()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
  v_count INTEGER := 0;
  v_msg TEXT;
BEGIN
  FOR r IN
    SELECT id, title, organizer_id
    FROM public.events
    WHERE status = 'active'
      AND event_date < NOW()
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE public.events
    SET status = 'finished',
        finished_at = NOW(),
        updated_at = NOW()
    WHERE id = r.id;

    PERFORM public.ensure_event_chat(r.id);

    v_msg := 'Мероприятие «' || r.title || '» завершено. '
          || 'Чат доступен ещё 3 дня. Писать могут только организатор и помощник.';

    PERFORM public.post_event_chat_message(
      r.id,
      r.organizer_id,
      'system',
      v_msg,
      jsonb_build_object(
        'kind', 'event_finished',
        'title', r.title
      )
    );

    v_count := v_count + 1;
  END LOOP;

  -- Purge chats for events finished > 3 days ago
  DELETE FROM public.conversations c
  USING public.events e
  WHERE c.type = 'event'
    AND c.event_id = e.id
    AND e.status = 'finished'
    AND e.finished_at IS NOT NULL
    AND e.finished_at < NOW() - INTERVAL '3 days';

  RETURN v_count;
END;
$$;

-- ---------- Assign / clear assistant (organizer only) ----------
CREATE OR REPLACE FUNCTION public.set_event_assistant(
  p_event_id UUID,
  p_user_id UUID
)
RETURNS public.events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_event public.events%ROWTYPE;
  v_registered BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_event
  FROM public.events
  WHERE id = p_event_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_event.organizer_id IS DISTINCT FROM v_uid AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_USER' USING ERRCODE = 'P0001';
  END IF;

  IF p_user_id = v_event.organizer_id THEN
    RAISE EXCEPTION 'CANNOT_ASSIGN_SELF' USING ERRCODE = 'P0001';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.event_participants ep
    WHERE ep.event_id = p_event_id
      AND ep.user_id = p_user_id
      AND ep.registration_status = 'registered'
  ) INTO v_registered;

  IF NOT v_registered THEN
    RAISE EXCEPTION 'NOT_PARTICIPANT' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.events
  SET assistant_user_id = p_user_id,
      updated_at = NOW()
  WHERE id = p_event_id
  RETURNING * INTO v_event;

  PERFORM public.ensure_event_chat(p_event_id);

  RETURN v_event;
END;
$$;

CREATE OR REPLACE FUNCTION public.clear_event_assistant(p_event_id UUID)
RETURNS public.events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_event public.events%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_event
  FROM public.events
  WHERE id = p_event_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_event.organizer_id IS DISTINCT FROM v_uid AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  UPDATE public.events
  SET assistant_user_id = NULL,
      updated_at = NOW()
  WHERE id = p_event_id
  RETURNING * INTO v_event;

  RETURN v_event;
END;
$$;

REVOKE ALL ON FUNCTION public.set_event_assistant(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_event_assistant(UUID, UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.clear_event_assistant(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.clear_event_assistant(UUID) TO authenticated;

-- ---------- Submit report ----------
CREATE OR REPLACE FUNCTION public.submit_event_report(
  p_event_id UUID,
  p_winner TEXT,
  p_score_light INTEGER,
  p_score_dark INTEGER
)
RETURNS public.events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_event public.events%ROWTYPE;
  v_winner TEXT := lower(btrim(COALESCE(p_winner, '')));
  v_payload JSONB;
  v_text TEXT;
  v_winner_label TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_event
  FROM public.events
  WHERE id = p_event_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF NOT public.is_event_manager(p_event_id, v_uid) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF v_event.status <> 'finished' THEN
    RAISE EXCEPTION 'EVENT_NOT_FINISHED' USING ERRCODE = 'P0001';
  END IF;

  IF v_event.report_submitted_at IS NOT NULL THEN
    RAISE EXCEPTION 'REPORT_ALREADY_SUBMITTED' USING ERRCODE = 'P0001';
  END IF;

  IF v_winner NOT IN ('light', 'dark', 'draw') THEN
    RAISE EXCEPTION 'INVALID_WINNER' USING ERRCODE = 'P0001';
  END IF;

  IF p_score_light IS NULL OR p_score_dark IS NULL
     OR p_score_light < 0 OR p_score_dark < 0 THEN
    RAISE EXCEPTION 'INVALID_SCORE' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.events
  SET report_winner = v_winner,
      report_score_light = p_score_light,
      report_score_dark = p_score_dark,
      report_submitted_at = NOW(),
      updated_at = NOW()
  WHERE id = p_event_id
  RETURNING * INTO v_event;

  v_winner_label := CASE v_winner
    WHEN 'light' THEN 'Зелёная команда'
    WHEN 'dark' THEN 'Красная команда'
    ELSE 'Ничья'
  END;

  v_payload := jsonb_build_object(
    'title', 'Итоги игры',
    'event_title', v_event.title,
    'winner', v_winner,
    'winner_label', v_winner_label,
    'score_light', p_score_light,
    'score_dark', p_score_dark
  );

  v_text := 'Итоги: ' || v_winner_label
         || ' · ' || p_score_light::TEXT || ':' || p_score_dark::TEXT;

  PERFORM public.ensure_event_chat(p_event_id);
  PERFORM public.post_event_chat_message(
    p_event_id,
    v_uid,
    'event_report',
    v_text,
    v_payload
  );

  RETURN v_event;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_event_report(UUID, TEXT, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_event_report(UUID, TEXT, INTEGER, INTEGER) TO authenticated;

-- ---------- confirm_event_attendance: managers ----------
CREATE OR REPLACE FUNCTION public.confirm_event_attendance(
  p_event_id UUID,
  p_public_qr_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_event public.events%ROWTYPE;
  v_user public.profiles%ROWTYPE;
  v_part public.event_participants%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_event FROM public.events WHERE id = p_event_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF NOT public.is_event_manager(p_event_id, v_uid) THEN
    RAISE EXCEPTION 'NOT_EVENT_OWNER' USING ERRCODE = '42501';
  END IF;

  IF v_event.status <> 'active' THEN
    IF v_event.status = 'finished' THEN
      RAISE EXCEPTION 'EVENT_FINISHED' USING ERRCODE = 'P0001';
    ELSIF v_event.status = 'cancelled' THEN
      RAISE EXCEPTION 'EVENT_CANCELLED' USING ERRCODE = 'P0001';
    ELSE
      RAISE EXCEPTION 'EVENT_NOT_ACTIVE' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  SELECT * INTO v_user FROM public.profiles WHERE public_qr_id = p_public_qr_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_part
  FROM public.event_participants
  WHERE event_id = p_event_id AND user_id = v_user.id
  FOR UPDATE;

  IF NOT FOUND OR v_part.registration_status <> 'registered' THEN
    RAISE EXCEPTION 'NOT_REGISTERED' USING ERRCODE = 'P0001';
  END IF;

  IF v_part.attendance_status = 'confirmed' THEN
    RAISE EXCEPTION 'ALREADY_CONFIRMED' USING ERRCODE = 'P0001';
  END IF;

  RETURN public._award_attendance_reward(v_event, v_part, v_user, v_uid);
END;
$$;

-- ---------- update_event: allow managers ----------
CREATE OR REPLACE FUNCTION public.update_event(
  p_event_id UUID,
  p_title TEXT,
  p_description TEXT,
  p_city TEXT,
  p_location TEXT,
  p_event_date TIMESTAMPTZ,
  p_max_participants INTEGER,
  p_image_url TEXT DEFAULT NULL,
  p_clear_image BOOLEAN DEFAULT FALSE,
  p_status TEXT DEFAULT NULL,
  p_polygon_id UUID DEFAULT NULL,
  p_latitude DOUBLE PRECISION DEFAULT NULL,
  p_longitude DOUBLE PRECISION DEFAULT NULL,
  p_rules_id UUID DEFAULT NULL,
  p_clear_rules BOOLEAN DEFAULT FALSE,
  p_rules_text TEXT DEFAULT NULL,
  p_set_rules_text BOOLEAN DEFAULT FALSE,
  p_radio_frequency TEXT DEFAULT NULL
)
RETURNS public.events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_old public.events%ROWTYPE;
  v_new public.events%ROWTYPE;
  v_status TEXT;
  v_city TEXT := btrim(COALESCE(p_city, ''));
  v_location TEXT := btrim(COALESCE(p_location, ''));
  v_lat DOUBLE PRECISION := p_latitude;
  v_lng DOUBLE PRECISION := p_longitude;
  v_polygon public.polygons%ROWTYPE;
  v_rules public.event_rules%ROWTYPE;
  v_registered INTEGER;
  v_image TEXT;
  v_rules_id UUID;
  v_rules_text TEXT;
  v_custom TEXT := NULLIF(btrim(COALESCE(p_rules_text, '')), '');
  v_radio TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_old
  FROM public.events
  WHERE id = p_event_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF NOT public.is_event_manager(p_event_id, v_uid) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  v_status := COALESCE(NULLIF(trim(p_status), ''), v_old.status);
  IF v_status NOT IN ('draft', 'active', 'finished', 'cancelled') THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING ERRCODE = 'P0001';
  END IF;

  IF p_title IS NULL OR char_length(trim(p_title)) < 2 THEN
    RAISE EXCEPTION 'INVALID_TITLE' USING ERRCODE = 'P0001';
  END IF;

  IF p_max_participants IS NULL OR p_max_participants < 1 THEN
    RAISE EXCEPTION 'INVALID_LIMIT' USING ERRCODE = 'P0001';
  END IF;

  IF p_event_date IS NULL THEN
    RAISE EXCEPTION 'INVALID_DATE' USING ERRCODE = 'P0001';
  END IF;

  SELECT COUNT(*)::INTEGER INTO v_registered
  FROM public.event_participants
  WHERE event_id = p_event_id
    AND registration_status = 'registered';

  IF p_max_participants < v_registered THEN
    RAISE EXCEPTION 'LIMIT_BELOW_PARTICIPANTS' USING ERRCODE = 'P0001';
  END IF;

  IF p_polygon_id IS NOT NULL THEN
    SELECT * INTO v_polygon
    FROM public.polygons
    WHERE id = p_polygon_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'POLYGON_NOT_FOUND' USING ERRCODE = 'P0001';
    END IF;

    IF v_polygon.organizer_id <> v_old.organizer_id THEN
      RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
    END IF;

    v_city := v_polygon.city;
    IF char_length(v_location) < 2 THEN
      v_location := v_polygon.name;
    END IF;
    v_lat := v_polygon.latitude;
    v_lng := v_polygon.longitude;
  END IF;

  IF char_length(v_city) < 2 THEN
    RAISE EXCEPTION 'INVALID_CITY' USING ERRCODE = 'P0001';
  END IF;

  IF char_length(v_location) < 2 THEN
    RAISE EXCEPTION 'INVALID_LOCATION' USING ERRCODE = 'P0001';
  END IF;

  IF v_lat IS NULL OR v_lng IS NULL THEN
    RAISE EXCEPTION 'MAP_LOCATION_REQUIRED' USING ERRCODE = 'P0001';
  END IF;

  IF v_lat < -90 OR v_lat > 90 OR v_lng < -180 OR v_lng > 180 THEN
    RAISE EXCEPTION 'INVALID_COORDINATES' USING ERRCODE = 'P0001';
  END IF;

  IF p_clear_image THEN
    v_image := NULL;
  ELSIF p_image_url IS NOT NULL AND btrim(p_image_url) <> '' THEN
    v_image := btrim(p_image_url);
  ELSE
    v_image := v_old.image_url;
  END IF;

  IF p_radio_frequency IS NULL THEN
    v_radio := COALESCE(v_old.radio_frequency, '');
  ELSE
    v_radio := btrim(p_radio_frequency);
  END IF;

  IF char_length(v_radio) > 40 THEN
    RAISE EXCEPTION 'INVALID_RADIO_FREQUENCY' USING ERRCODE = 'P0001';
  END IF;

  IF p_clear_rules THEN
    v_rules_id := NULL;
    v_rules_text := '';
  ELSE
    v_rules_id := v_old.rules_id;
    v_rules_text := COALESCE(v_old.rules_text, '');

    IF p_rules_id IS NOT NULL THEN
      SELECT * INTO v_rules
      FROM public.event_rules
      WHERE id = p_rules_id;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'RULES_NOT_FOUND' USING ERRCODE = 'P0001';
      END IF;

      IF v_rules.organizer_id <> v_old.organizer_id THEN
        RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
      END IF;

      v_rules_id := v_rules.id;
      v_rules_text := v_rules.body;
    END IF;

    IF p_set_rules_text THEN
      IF v_custom IS NULL THEN
        v_rules_id := NULL;
        v_rules_text := '';
      ELSE
        IF char_length(v_custom) > 20000 THEN
          RAISE EXCEPTION 'INVALID_RULES_BODY' USING ERRCODE = 'P0001';
        END IF;
        v_rules_text := v_custom;
      END IF;
    END IF;
  END IF;

  UPDATE public.events SET
    title = trim(p_title),
    description = COALESCE(trim(p_description), ''),
    city = v_city,
    location = v_location,
    event_date = p_event_date,
    max_participants = p_max_participants,
    image_url = v_image,
    status = v_status,
    polygon_id = p_polygon_id,
    latitude = v_lat,
    longitude = v_lng,
    rules_id = v_rules_id,
    rules_text = v_rules_text,
    radio_frequency = v_radio
  WHERE id = p_event_id
  RETURNING * INTO v_new;

  IF v_new.status IN ('draft', 'active', 'finished') THEN
    PERFORM public.ensure_event_chat(p_event_id);
  END IF;

  RETURN v_new;
END;
$$;

NOTIFY pgrst, 'reload schema';
