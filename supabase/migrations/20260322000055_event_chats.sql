-- ============================================================
-- Event chats: create with event, join on participate, delete on end
-- ============================================================

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS event_id UUID
    REFERENCES public.events (id) ON DELETE CASCADE;

CREATE UNIQUE INDEX IF NOT EXISTS conversations_event_unique_idx
  ON public.conversations (event_id)
  WHERE type = 'event' AND event_id IS NOT NULL;

ALTER TABLE public.conversations DROP CONSTRAINT IF EXISTS conversations_type_check;
ALTER TABLE public.conversations
  ADD CONSTRAINT conversations_type_check
  CHECK (type IN ('market', 'clan', 'user', 'city', 'dating', 'event'));

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
      AND event_id IS NULL
    )
    OR (
      type = 'clan'
      AND clan_id IS NOT NULL
      AND listing_id IS NULL
      AND city_name IS NULL
      AND dating_match_id IS NULL
      AND event_id IS NULL
    )
    OR (
      type = 'user'
      AND listing_id IS NULL
      AND clan_id IS NULL
      AND city_name IS NULL
      AND dating_match_id IS NULL
      AND event_id IS NULL
    )
    OR (
      type = 'city'
      AND city_name IS NOT NULL
      AND listing_id IS NULL
      AND clan_id IS NULL
      AND clan_channel IS NULL
      AND dating_match_id IS NULL
      AND event_id IS NULL
    )
    OR (
      type = 'dating'
      AND listing_id IS NULL
      AND clan_id IS NULL
      AND city_name IS NULL
      AND clan_channel IS NULL
      AND event_id IS NULL
    )
    OR (
      type = 'event'
      AND event_id IS NOT NULL
      AND listing_id IS NULL
      AND clan_id IS NULL
      AND city_name IS NULL
      AND dating_match_id IS NULL
      AND clan_channel IS NULL
    )
  );

-- ---------- Finish past active events (event_date elapsed) ----------
CREATE OR REPLACE FUNCTION public.auto_finish_past_events()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  WITH finished AS (
    UPDATE public.events
    SET status = 'finished',
        updated_at = NOW()
    WHERE status = 'active'
      AND event_date < NOW()
    RETURNING id
  )
  SELECT COUNT(*)::INTEGER INTO v_count FROM finished;
  RETURN COALESCE(v_count, 0);
END;
$$;

REVOKE ALL ON FUNCTION public.auto_finish_past_events() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.auto_finish_past_events() TO authenticated;

-- ---------- Ensure event chat + organizer membership ----------
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

  IF v_event.status IN ('finished', 'cancelled') THEN
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

  RETURN v_conv;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_event_chat(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_event_chat(UUID) TO authenticated;

-- ---------- Participant ↔ chat membership sync ----------
CREATE OR REPLACE FUNCTION public.sync_event_conversation_member()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event_id UUID;
  v_user_id UUID;
  v_conv UUID;
  v_organizer UUID;
  v_status TEXT;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_event_id := OLD.event_id;
    v_user_id := OLD.user_id;
  ELSE
    v_event_id := NEW.event_id;
    v_user_id := NEW.user_id;
  END IF;

  SELECT organizer_id, status INTO v_organizer, v_status
  FROM public.events
  WHERE id = v_event_id;

  IF NOT FOUND THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF v_status IN ('finished', 'cancelled') THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  v_conv := public.ensure_event_chat(v_event_id);
  IF v_conv IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.registration_status = 'registered' THEN
      INSERT INTO public.conversation_members (conversation_id, user_id, role, last_read_at)
      VALUES (v_conv, v_user_id, 'member', NOW())
      ON CONFLICT (conversation_id, user_id) DO NOTHING;
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.registration_status = 'registered'
       AND OLD.registration_status IS DISTINCT FROM 'registered' THEN
      INSERT INTO public.conversation_members (conversation_id, user_id, role, last_read_at)
      VALUES (v_conv, v_user_id, 'member', NOW())
      ON CONFLICT (conversation_id, user_id) DO NOTHING;
    ELSIF NEW.registration_status = 'cancelled'
          AND OLD.registration_status = 'registered'
          AND v_user_id IS DISTINCT FROM v_organizer THEN
      DELETE FROM public.conversation_members
      WHERE conversation_id = v_conv AND user_id = v_user_id;
    END IF;
  ELSIF TG_OP = 'DELETE' THEN
    IF v_user_id IS DISTINCT FROM v_organizer THEN
      DELETE FROM public.conversation_members
      WHERE conversation_id = v_conv AND user_id = v_user_id;
    END IF;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS event_participants_sync_chat ON public.event_participants;
CREATE TRIGGER event_participants_sync_chat
  AFTER INSERT OR UPDATE OF registration_status OR DELETE
  ON public.event_participants
  FOR EACH ROW
  EXECUTE PROCEDURE public.sync_event_conversation_member();

-- ---------- Delete chat when event finishes / cancelled ----------
CREATE OR REPLACE FUNCTION public.delete_event_conversation_on_end()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IN ('finished', 'cancelled')
     AND OLD.status IS DISTINCT FROM NEW.status THEN
    DELETE FROM public.conversations
    WHERE type = 'event' AND event_id = NEW.id;
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

DROP TRIGGER IF EXISTS events_delete_chat_on_end ON public.events;
CREATE TRIGGER events_delete_chat_on_end
  AFTER UPDATE OF status, title
  ON public.events
  FOR EACH ROW
  EXECUTE PROCEDURE public.delete_event_conversation_on_end();

-- ---------- Organizer finishes event ----------
CREATE OR REPLACE FUNCTION public.finish_event(p_event_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_org UUID;
  v_status TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT organizer_id, status INTO v_org, v_status
  FROM public.events
  WHERE id = p_event_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_org IS DISTINCT FROM v_uid AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF v_status IN ('finished', 'cancelled') THEN
    RETURN;
  END IF;

  UPDATE public.events
  SET status = 'finished',
      updated_at = NOW()
  WHERE id = p_event_id;
END;
$$;

REVOKE ALL ON FUNCTION public.finish_event(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.finish_event(UUID) TO authenticated;

-- ---------- Hook create_event ----------
CREATE OR REPLACE FUNCTION public.create_event(
  p_title TEXT,
  p_description TEXT,
  p_city TEXT,
  p_location TEXT,
  p_event_date TIMESTAMPTZ,
  p_max_participants INTEGER,
  p_image_url TEXT DEFAULT NULL,
  p_status TEXT DEFAULT 'active',
  p_polygon_id UUID DEFAULT NULL,
  p_latitude DOUBLE PRECISION DEFAULT NULL,
  p_longitude DOUBLE PRECISION DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_id UUID;
  v_status TEXT := COALESCE(NULLIF(trim(p_status), ''), 'active');
  v_city TEXT := btrim(COALESCE(p_city, ''));
  v_location TEXT := btrim(COALESCE(p_location, ''));
  v_lat DOUBLE PRECISION := p_latitude;
  v_lng DOUBLE PRECISION := p_longitude;
  v_polygon public.polygons%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_organizer() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

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

  IF p_polygon_id IS NOT NULL THEN
    SELECT * INTO v_polygon
    FROM public.polygons
    WHERE id = p_polygon_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'POLYGON_NOT_FOUND' USING ERRCODE = 'P0001';
    END IF;

    IF v_polygon.organizer_id <> v_uid THEN
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

  INSERT INTO public.events (
    organizer_id, title, description, city, location,
    event_date, max_participants, image_url, status,
    polygon_id, latitude, longitude
  )
  VALUES (
    v_uid,
    trim(p_title),
    COALESCE(trim(p_description), ''),
    v_city,
    v_location,
    p_event_date,
    p_max_participants,
    p_image_url,
    v_status,
    p_polygon_id,
    v_lat,
    v_lng
  )
  RETURNING id INTO v_id;

  IF v_status IN ('draft', 'active') THEN
    PERFORM public.ensure_event_chat(v_id);
  END IF;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_event(
  TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, INTEGER, TEXT, TEXT, UUID, DOUBLE PRECISION, DOUBLE PRECISION
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_event(
  TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, INTEGER, TEXT, TEXT, UUID, DOUBLE PRECISION, DOUBLE PRECISION
) TO authenticated;

-- ---------- Unread counts include event (+ auto-finish past) ----------
CREATE OR REPLACE FUNCTION public.conversation_unread_by_type()
RETURNS TABLE (
  type TEXT,
  unread_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.auto_finish_past_events();

  RETURN QUERY
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
    VALUES ('market'), ('clan'), ('user'), ('city'), ('dating'), ('event')
  ) AS t(type)
  LEFT JOIN unread u ON u.type = t.type;
END;
$$;

REVOKE ALL ON FUNCTION public.conversation_unread_by_type() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.conversation_unread_by_type() TO authenticated;

-- ---------- Backfill chats for existing draft/active events ----------
DO $$
DECLARE
  r RECORD;
  v_conv UUID;
BEGIN
  FOR r IN
    SELECT id
    FROM public.events
    WHERE status IN ('draft', 'active')
  LOOP
    v_conv := public.ensure_event_chat(r.id);
    IF v_conv IS NULL THEN
      CONTINUE;
    END IF;

    INSERT INTO public.conversation_members (conversation_id, user_id, role, last_read_at)
    SELECT v_conv, ep.user_id, 'member', NOW()
    FROM public.event_participants ep
    WHERE ep.event_id = r.id
      AND ep.registration_status = 'registered'
    ON CONFLICT (conversation_id, user_id) DO NOTHING;
  END LOOP;
END;
$$;
