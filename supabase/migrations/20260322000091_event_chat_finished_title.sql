-- Event chat title becomes «Окончено» after finish

CREATE OR REPLACE FUNCTION public.ensure_event_chat(p_event_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event public.events%ROWTYPE;
  v_conv UUID;
  v_title TEXT;
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

  v_title := CASE
    WHEN v_event.status = 'finished' THEN 'Окончено'
    ELSE v_event.title
  END;

  SELECT id INTO v_conv
  FROM public.conversations
  WHERE type = 'event' AND event_id = p_event_id
  LIMIT 1;

  IF v_conv IS NULL THEN
    INSERT INTO public.conversations (type, title, event_id)
    VALUES ('event', v_title, p_event_id)
    RETURNING id INTO v_conv;
  ELSE
    UPDATE public.conversations
    SET title = v_title
    WHERE id = v_conv
      AND title IS DISTINCT FROM v_title;
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
    SET title = CASE
      WHEN NEW.status = 'finished' THEN 'Окончено'
      ELSE NEW.title
    END
    WHERE type = 'event' AND event_id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;

-- Existing finished event chats
UPDATE public.conversations c
SET title = 'Окончено'
FROM public.events e
WHERE c.type = 'event'
  AND c.event_id = e.id
  AND e.status = 'finished'
  AND c.title IS DISTINCT FROM 'Окончено';

NOTIFY pgrst, 'reload schema';
