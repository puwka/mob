-- Event organizer radio frequency

ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS radio_frequency TEXT NOT NULL DEFAULT '';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'events_radio_frequency_len'
  ) THEN
    ALTER TABLE public.events
      ADD CONSTRAINT events_radio_frequency_len
      CHECK (char_length(radio_frequency) <= 40);
  END IF;
END $$;

DROP FUNCTION IF EXISTS public.create_event(
  TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, INTEGER, TEXT, TEXT, UUID, DOUBLE PRECISION, DOUBLE PRECISION, UUID, TEXT
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
  p_rules_id UUID DEFAULT NULL,
  p_rules_text TEXT DEFAULT NULL,
  p_radio_frequency TEXT DEFAULT NULL
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
  v_custom TEXT := NULLIF(btrim(COALESCE(p_rules_text, '')), '');
  v_radio TEXT := btrim(COALESCE(p_radio_frequency, ''));
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

  IF char_length(v_radio) > 40 THEN
    RAISE EXCEPTION 'INVALID_RADIO_FREQUENCY' USING ERRCODE = 'P0001';
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

  IF p_rules_text IS NOT NULL THEN
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

  INSERT INTO public.events (
    organizer_id, title, description, city, location,
    event_date, max_participants, image_url, status,
    polygon_id, latitude, longitude,
    rules_id, rules_text, radio_frequency
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
    v_rules_text,
    v_radio
  )
  RETURNING id INTO v_id;

  IF v_status IN ('draft', 'active') THEN
    PERFORM public.ensure_event_chat(v_id);
  END IF;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_event(
  TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, INTEGER, TEXT, TEXT, UUID, DOUBLE PRECISION, DOUBLE PRECISION, UUID, TEXT, TEXT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_event(
  TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, INTEGER, TEXT, TEXT, UUID, DOUBLE PRECISION, DOUBLE PRECISION, UUID, TEXT, TEXT
) TO authenticated;

DROP FUNCTION IF EXISTS public.update_event(
  UUID, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, INTEGER,
  TEXT, BOOLEAN, TEXT, UUID, DOUBLE PRECISION, DOUBLE PRECISION, UUID, BOOLEAN, TEXT, BOOLEAN
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

      IF v_rules.organizer_id <> v_uid THEN
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

  IF v_new.status IN ('draft', 'active') THEN
    PERFORM public.ensure_event_chat(p_event_id);
  END IF;

  RETURN v_new;
END;
$$;

REVOKE ALL ON FUNCTION public.update_event(
  UUID, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, INTEGER,
  TEXT, BOOLEAN, TEXT, UUID, DOUBLE PRECISION, DOUBLE PRECISION, UUID, BOOLEAN, TEXT, BOOLEAN, TEXT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_event(
  UUID, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, INTEGER,
  TEXT, BOOLEAN, TEXT, UUID, DOUBLE PRECISION, DOUBLE PRECISION, UUID, BOOLEAN, TEXT, BOOLEAN, TEXT
) TO authenticated;

NOTIFY pgrst, 'reload schema';
