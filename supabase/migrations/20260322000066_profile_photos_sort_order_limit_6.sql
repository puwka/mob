-- Fix gallery: table still had CHECK (sort_order < 4) after limit was raised to 6.
-- 5th photo got sort_order=4 and failed the old constraint.

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT c.conname
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public'
      AND t.relname = 'profile_photos'
      AND c.contype = 'c'
      AND pg_get_constraintdef(c.oid) ILIKE '%sort_order%'
  LOOP
    EXECUTE format(
      'ALTER TABLE public.profile_photos DROP CONSTRAINT %I',
      r.conname
    );
  END LOOP;
END $$;

ALTER TABLE public.profile_photos
  ADD CONSTRAINT profile_photos_sort_order_check
  CHECK (sort_order >= 0 AND sort_order < 6);


UPDATE public.app_settings
SET value = '6', updated_at = NOW()
WHERE key = 'profile_photos_limit';

INSERT INTO public.app_settings (key, value)
SELECT 'profile_photos_limit', '6'
WHERE NOT EXISTS (
  SELECT 1 FROM public.app_settings WHERE key = 'profile_photos_limit'
);

CREATE OR REPLACE FUNCTION public.enforce_profile_photos_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_count INTEGER;
  v_limit INTEGER := 6;
BEGIN
  BEGIN
    SELECT NULLIF(btrim(value), '')::INTEGER INTO v_limit
    FROM public.app_settings
    WHERE key = 'profile_photos_limit';
  EXCEPTION WHEN OTHERS THEN
    v_limit := 6;
  END;

  IF v_limit IS NULL OR v_limit < 1 THEN
    v_limit := 6;
  END IF;

  SELECT COUNT(*)::INTEGER INTO v_count
  FROM public.profile_photos
  WHERE user_id = NEW.user_id;

  IF TG_OP = 'INSERT' AND v_count >= v_limit THEN
    RAISE EXCEPTION 'PHOTO_LIMIT' USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

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
  v_limit INTEGER := 6;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF p_url IS NULL OR btrim(p_url) = '' THEN
    RAISE EXCEPTION 'INVALID_URL' USING ERRCODE = 'P0001';
  END IF;

  BEGIN
    SELECT NULLIF(btrim(value), '')::INTEGER INTO v_limit
    FROM public.app_settings
    WHERE key = 'profile_photos_limit';
  EXCEPTION WHEN OTHERS THEN
    v_limit := 6;
  END;

  IF v_limit IS NULL OR v_limit < 1 THEN
    v_limit := 6;
  END IF;

  -- Cap by column CHECK (sort_order < 6)
  IF v_limit > 6 THEN
    v_limit := 6;
  END IF;

  IF (
    SELECT COUNT(*) FROM public.profile_photos WHERE user_id = v_uid
  ) >= v_limit THEN
    RAISE EXCEPTION 'PHOTO_LIMIT' USING ERRCODE = 'P0001';
  END IF;

  SELECT s.ord INTO v_order
  FROM generate_series(0, v_limit - 1) AS s(ord)
  WHERE NOT EXISTS (
    SELECT 1 FROM public.profile_photos p
    WHERE p.user_id = v_uid AND p.sort_order = s.ord
  )
  ORDER BY s.ord
  LIMIT 1;

  IF v_order IS NULL THEN
    RAISE EXCEPTION 'PHOTO_LIMIT' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.profile_photos (user_id, url, sort_order)
  VALUES (v_uid, btrim(p_url), v_order)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

NOTIFY pgrst, 'reload schema';
