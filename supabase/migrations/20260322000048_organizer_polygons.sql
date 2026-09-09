-- ============================================================
-- Organizer polygons (venues) + event map coordinates
-- ============================================================

CREATE TABLE IF NOT EXISTS public.polygons (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organizer_id UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  city TEXT NOT NULL,
  address TEXT NOT NULL,
  latitude DOUBLE PRECISION NOT NULL
    CHECK (latitude >= -90 AND latitude <= 90),
  longitude DOUBLE PRECISION NOT NULL
    CHECK (longitude >= -180 AND longitude <= 180),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT polygons_name_len CHECK (char_length(btrim(name)) BETWEEN 2 AND 120),
  CONSTRAINT polygons_city_len CHECK (char_length(btrim(city)) BETWEEN 2 AND 80),
  CONSTRAINT polygons_address_len CHECK (char_length(btrim(address)) BETWEEN 2 AND 240)
);

CREATE INDEX IF NOT EXISTS polygons_organizer_idx
  ON public.polygons (organizer_id);

CREATE INDEX IF NOT EXISTS polygons_city_idx
  ON public.polygons (lower(city));

ALTER TABLE public.polygons ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Polygons readable authenticated" ON public.polygons;
CREATE POLICY "Polygons readable authenticated"
  ON public.polygons
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Organizers manage own polygons" ON public.polygons;
CREATE POLICY "Organizers manage own polygons"
  ON public.polygons
  FOR ALL
  TO authenticated
  USING (organizer_id = auth.uid() AND public.is_organizer())
  WITH CHECK (organizer_id = auth.uid() AND public.is_organizer());

ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS polygon_id UUID
    REFERENCES public.polygons (id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION
    CHECK (latitude IS NULL OR (latitude >= -90 AND latitude <= 90)),
  ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION
    CHECK (longitude IS NULL OR (longitude >= -180 AND longitude <= 180));

CREATE INDEX IF NOT EXISTS events_polygon_idx ON public.events (polygon_id);

CREATE OR REPLACE FUNCTION public.create_polygon(
  p_name TEXT,
  p_city TEXT,
  p_address TEXT,
  p_latitude DOUBLE PRECISION,
  p_longitude DOUBLE PRECISION
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_id UUID;
  v_name TEXT := btrim(COALESCE(p_name, ''));
  v_city TEXT := btrim(COALESCE(p_city, ''));
  v_address TEXT := btrim(COALESCE(p_address, ''));
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_organizer() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF char_length(v_name) < 2 OR char_length(v_name) > 120 THEN
    RAISE EXCEPTION 'INVALID_POLYGON_NAME' USING ERRCODE = 'P0001';
  END IF;

  IF char_length(v_city) < 2 OR char_length(v_city) > 80 THEN
    RAISE EXCEPTION 'INVALID_CITY' USING ERRCODE = 'P0001';
  END IF;

  IF char_length(v_address) < 2 OR char_length(v_address) > 240 THEN
    RAISE EXCEPTION 'INVALID_ADDRESS' USING ERRCODE = 'P0001';
  END IF;

  IF p_latitude IS NULL OR p_longitude IS NULL
     OR p_latitude < -90 OR p_latitude > 90
     OR p_longitude < -180 OR p_longitude > 180 THEN
    RAISE EXCEPTION 'INVALID_COORDINATES' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.polygons (
    organizer_id, name, city, address, latitude, longitude
  )
  VALUES (
    v_uid, v_name, v_city, v_address, p_latitude, p_longitude
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_polygon(TEXT, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_polygon(TEXT, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_polygon(
  p_polygon_id UUID,
  p_name TEXT,
  p_city TEXT,
  p_address TEXT,
  p_latitude DOUBLE PRECISION,
  p_longitude DOUBLE PRECISION
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_name TEXT := btrim(COALESCE(p_name, ''));
  v_city TEXT := btrim(COALESCE(p_city, ''));
  v_address TEXT := btrim(COALESCE(p_address, ''));
  v_owner UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_organizer() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  SELECT organizer_id INTO v_owner
  FROM public.polygons
  WHERE id = p_polygon_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'POLYGON_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  IF v_owner <> v_uid THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF char_length(v_name) < 2 OR char_length(v_name) > 120 THEN
    RAISE EXCEPTION 'INVALID_POLYGON_NAME' USING ERRCODE = 'P0001';
  END IF;

  IF char_length(v_city) < 2 OR char_length(v_city) > 80 THEN
    RAISE EXCEPTION 'INVALID_CITY' USING ERRCODE = 'P0001';
  END IF;

  IF char_length(v_address) < 2 OR char_length(v_address) > 240 THEN
    RAISE EXCEPTION 'INVALID_ADDRESS' USING ERRCODE = 'P0001';
  END IF;

  IF p_latitude IS NULL OR p_longitude IS NULL
     OR p_latitude < -90 OR p_latitude > 90
     OR p_longitude < -180 OR p_longitude > 180 THEN
    RAISE EXCEPTION 'INVALID_COORDINATES' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.polygons
  SET
    name = v_name,
    city = v_city,
    address = v_address,
    latitude = p_latitude,
    longitude = p_longitude,
    updated_at = NOW()
  WHERE id = p_polygon_id;
END;
$$;

REVOKE ALL ON FUNCTION public.update_polygon(UUID, TEXT, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_polygon(UUID, TEXT, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_polygon(p_polygon_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_owner UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_organizer() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  SELECT organizer_id INTO v_owner
  FROM public.polygons
  WHERE id = p_polygon_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'POLYGON_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  IF v_owner <> v_uid THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.polygons WHERE id = p_polygon_id;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_polygon(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_polygon(UUID) TO authenticated;

DROP FUNCTION IF EXISTS public.create_event(TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, INTEGER, TEXT, TEXT);

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

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_event(
  TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, INTEGER, TEXT, TEXT, UUID, DOUBLE PRECISION, DOUBLE PRECISION
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_event(
  TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, INTEGER, TEXT, TEXT, UUID, DOUBLE PRECISION, DOUBLE PRECISION
) TO authenticated;

NOTIFY pgrst, 'reload schema';
