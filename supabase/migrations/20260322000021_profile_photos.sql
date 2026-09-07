-- ============================================================
-- Profile gallery: max 4 photos per user
-- ============================================================

CREATE TABLE IF NOT EXISTS public.profile_photos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  url TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0
    CHECK (sort_order >= 0 AND sort_order < 4),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, sort_order)
);

CREATE INDEX IF NOT EXISTS profile_photos_user_idx
  ON public.profile_photos (user_id, sort_order);

ALTER TABLE public.profile_photos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Profile photos readable" ON public.profile_photos;
CREATE POLICY "Profile photos readable"
  ON public.profile_photos
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Users manage own profile photos" ON public.profile_photos;
CREATE POLICY "Users manage own profile photos"
  ON public.profile_photos
  FOR ALL
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Enforce max 4 photos per user
CREATE OR REPLACE FUNCTION public.enforce_profile_photos_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  SELECT COUNT(*)::INTEGER INTO v_count
  FROM public.profile_photos
  WHERE user_id = NEW.user_id;

  IF TG_OP = 'INSERT' AND v_count >= 4 THEN
    RAISE EXCEPTION 'PHOTO_LIMIT' USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profile_photos_limit_bi ON public.profile_photos;
CREATE TRIGGER profile_photos_limit_bi
  BEFORE INSERT ON public.profile_photos
  FOR EACH ROW
  EXECUTE PROCEDURE public.enforce_profile_photos_limit();

-- RPC: add photo (assigns next free sort_order 0..3)
CREATE OR REPLACE FUNCTION public.add_profile_photo(p_url TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_order INTEGER;
  v_id UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF p_url IS NULL OR btrim(p_url) = '' THEN
    RAISE EXCEPTION 'INVALID_URL' USING ERRCODE = 'P0001';
  END IF;

  IF (
    SELECT COUNT(*) FROM public.profile_photos WHERE user_id = v_uid
  ) >= 4 THEN
    RAISE EXCEPTION 'PHOTO_LIMIT' USING ERRCODE = 'P0001';
  END IF;

  SELECT s.ord INTO v_order
  FROM generate_series(0, 3) AS s(ord)
  WHERE NOT EXISTS (
    SELECT 1 FROM public.profile_photos p
    WHERE p.user_id = v_uid AND p.sort_order = s.ord
  )
  ORDER BY s.ord
  LIMIT 1;

  INSERT INTO public.profile_photos (user_id, url, sort_order)
  VALUES (v_uid, btrim(p_url), v_order)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.add_profile_photo(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.add_profile_photo(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_profile_photo(p_photo_id UUID)
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

  DELETE FROM public.profile_photos
  WHERE id = p_photo_id AND user_id = v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_profile_photo(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_profile_photo(UUID) TO authenticated;
