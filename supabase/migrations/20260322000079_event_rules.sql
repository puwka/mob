-- ============================================================
-- Organizer event rules templates + snapshot on events
-- ============================================================

CREATE TABLE IF NOT EXISTS public.event_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organizer_id UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT event_rules_title_len CHECK (char_length(btrim(title)) BETWEEN 2 AND 120),
  CONSTRAINT event_rules_body_len CHECK (char_length(btrim(body)) BETWEEN 1 AND 20000)
);

CREATE INDEX IF NOT EXISTS event_rules_organizer_idx
  ON public.event_rules (organizer_id);

ALTER TABLE public.event_rules ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Event rules readable authenticated" ON public.event_rules;
CREATE POLICY "Event rules readable authenticated"
  ON public.event_rules
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Organizers manage own event rules" ON public.event_rules;
CREATE POLICY "Organizers manage own event rules"
  ON public.event_rules
  FOR ALL
  TO authenticated
  USING (organizer_id = auth.uid() AND public.is_organizer())
  WITH CHECK (organizer_id = auth.uid() AND public.is_organizer());

ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS rules_id UUID
    REFERENCES public.event_rules (id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS rules_text TEXT NOT NULL DEFAULT '';

CREATE INDEX IF NOT EXISTS events_rules_idx ON public.events (rules_id);

-- ---------- CRUD RPCs ----------
CREATE OR REPLACE FUNCTION public.create_event_rule(
  p_title TEXT,
  p_body TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_id UUID;
  v_title TEXT := btrim(COALESCE(p_title, ''));
  v_body TEXT := btrim(COALESCE(p_body, ''));
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_organizer() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF char_length(v_title) < 2 OR char_length(v_title) > 120 THEN
    RAISE EXCEPTION 'INVALID_RULES_TITLE' USING ERRCODE = 'P0001';
  END IF;

  IF char_length(v_body) < 1 OR char_length(v_body) > 20000 THEN
    RAISE EXCEPTION 'INVALID_RULES_BODY' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.event_rules (organizer_id, title, body)
  VALUES (v_uid, v_title, v_body)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_event_rule(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_event_rule(TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_event_rule(
  p_rules_id UUID,
  p_title TEXT,
  p_body TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_title TEXT := btrim(COALESCE(p_title, ''));
  v_body TEXT := btrim(COALESCE(p_body, ''));
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_organizer() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF char_length(v_title) < 2 OR char_length(v_title) > 120 THEN
    RAISE EXCEPTION 'INVALID_RULES_TITLE' USING ERRCODE = 'P0001';
  END IF;

  IF char_length(v_body) < 1 OR char_length(v_body) > 20000 THEN
    RAISE EXCEPTION 'INVALID_RULES_BODY' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.event_rules
  SET
    title = v_title,
    body = v_body,
    updated_at = NOW()
  WHERE id = p_rules_id
    AND organizer_id = v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'RULES_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.update_event_rule(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_event_rule(UUID, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_event_rule(p_rules_id UUID)
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

  IF NOT public.is_organizer() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.event_rules
  WHERE id = p_rules_id
    AND organizer_id = v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'RULES_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_event_rule(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_event_rule(UUID) TO authenticated;

-- ---------- Hook create_event / update_event ----------
DROP FUNCTION IF EXISTS public.create_event(
  TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, INTEGER, TEXT, TEXT, UUID, DOUBLE PRECISION, DOUBLE PRECISION
);

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
  p_longitude DOUBLE PRECISION DEFAULT NULL,
  p_rules_id UUID DEFAULT NULL
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
  v_rules public.event_rules%ROWTYPE;
  v_rules_id UUID := NULL;
  v_rules_text TEXT := '';
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

  IF p_rules_id IS NOT NULL THEN
    SELECT * INTO v_rules
    FROM public.event_rules
    WHERE id = p_rules_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'RULES_NOT_FOUND' USING ERRCODE = 'P0001';
    END IF;

    IF v_rules.organizer_id <> v_uid THEN
      RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
    END IF;

    v_rules_id := v_rules.id;
    v_rules_text := v_rules.body;
  END IF;

  INSERT INTO public.events (
    organizer_id, title, description, city, location,
    event_date, max_participants, image_url, status,
    polygon_id, latitude, longitude,
    rules_id, rules_text
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
    v_lng,
    v_rules_id,
    v_rules_text
  )
  RETURNING id INTO v_id;

  IF v_status IN ('draft', 'active') THEN
    PERFORM public.ensure_event_chat(v_id);
  END IF;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_event(
  TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, INTEGER, TEXT, TEXT, UUID, DOUBLE PRECISION, DOUBLE PRECISION, UUID
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_event(
  TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, INTEGER, TEXT, TEXT, UUID, DOUBLE PRECISION, DOUBLE PRECISION, UUID
) TO authenticated;

DROP FUNCTION IF EXISTS public.update_event(
  UUID, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, INTEGER,
  TEXT, BOOLEAN, TEXT, UUID, DOUBLE PRECISION, DOUBLE PRECISION
);

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
  p_clear_rules BOOLEAN DEFAULT FALSE
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
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_organizer() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_old
  FROM public.events
  WHERE id = p_event_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_old.organizer_id IS DISTINCT FROM v_uid THEN
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

  IF p_clear_image THEN
    v_image := NULL;
  ELSIF p_image_url IS NOT NULL AND btrim(p_image_url) <> '' THEN
    v_image := btrim(p_image_url);
  ELSE
    v_image := v_old.image_url;
  END IF;

  IF p_clear_rules THEN
    v_rules_id := NULL;
    v_rules_text := '';
  ELSIF p_rules_id IS NOT NULL THEN
    SELECT * INTO v_rules
    FROM public.event_rules
    WHERE id = p_rules_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'RULES_NOT_FOUND' USING ERRCODE = 'P0001';
    END IF;

    IF v_rules.organizer_id <> v_uid THEN
      RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
    END IF;

    v_rules_id := v_rules.id;
    v_rules_text := v_rules.body;
  ELSE
    v_rules_id := v_old.rules_id;
    v_rules_text := COALESCE(v_old.rules_text, '');
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
    rules_text = v_rules_text
  WHERE id = p_event_id
  RETURNING * INTO v_new;

  IF v_new.status IN ('draft', 'active') THEN
    PERFORM public.ensure_event_chat(p_event_id);
  END IF;

  RETURN v_new;
END;
$$;

REVOKE ALL ON FUNCTION public.update_event(
  UUID, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, INTEGER,
  TEXT, BOOLEAN, TEXT, UUID, DOUBLE PRECISION, DOUBLE PRECISION, UUID, BOOLEAN
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_event(
  UUID, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, INTEGER,
  TEXT, BOOLEAN, TEXT, UUID, DOUBLE PRECISION, DOUBLE PRECISION, UUID, BOOLEAN
) TO authenticated;

NOTIFY pgrst, 'reload schema';
