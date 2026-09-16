-- Event photo gallery (multiple images per event)

CREATE TABLE IF NOT EXISTS public.event_images (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES public.events (id) ON DELETE CASCADE,
  url TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS event_images_event_idx
  ON public.event_images (event_id, sort_order);

INSERT INTO public.app_settings (key, value)
VALUES ('event_images_limit', '8')
ON CONFLICT (key) DO NOTHING;

-- Backfill existing covers
INSERT INTO public.event_images (event_id, url, sort_order)
SELECT e.id, e.image_url, 0
FROM public.events e
WHERE e.image_url IS NOT NULL
  AND btrim(e.image_url) <> ''
  AND NOT EXISTS (
    SELECT 1 FROM public.event_images ei WHERE ei.event_id = e.id
  );

ALTER TABLE public.event_images ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Event images readable" ON public.event_images;
CREATE POLICY "Event images readable"
  ON public.event_images
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Organizers insert event images" ON public.event_images;
CREATE POLICY "Organizers insert event images"
  ON public.event_images
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.is_organizer()
    AND EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = event_id
        AND e.organizer_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Organizers update event images" ON public.event_images;
CREATE POLICY "Organizers update event images"
  ON public.event_images
  FOR UPDATE
  TO authenticated
  USING (
    public.is_organizer()
    AND EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = event_id
        AND e.organizer_id = auth.uid()
    )
  )
  WITH CHECK (
    public.is_organizer()
    AND EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = event_id
        AND e.organizer_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Organizers delete event images" ON public.event_images;
CREATE POLICY "Organizers delete event images"
  ON public.event_images
  FOR DELETE
  TO authenticated
  USING (
    public.is_organizer()
    AND EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = event_id
        AND e.organizer_id = auth.uid()
    )
  );

-- Keep events.image_url in sync with first gallery photo
CREATE OR REPLACE FUNCTION public.sync_event_cover_from_images()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event_id UUID;
  v_cover TEXT;
BEGIN
  v_event_id := COALESCE(NEW.event_id, OLD.event_id);

  SELECT ei.url INTO v_cover
  FROM public.event_images ei
  WHERE ei.event_id = v_event_id
  ORDER BY ei.sort_order ASC, ei.created_at ASC
  LIMIT 1;

  UPDATE public.events
  SET image_url = v_cover
  WHERE id = v_event_id
    AND image_url IS DISTINCT FROM v_cover;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS event_images_sync_cover ON public.event_images;
CREATE TRIGGER event_images_sync_cover
  AFTER INSERT OR UPDATE OR DELETE ON public.event_images
  FOR EACH ROW
  EXECUTE PROCEDURE public.sync_event_cover_from_images();

-- Enforce gallery limit
CREATE OR REPLACE FUNCTION public.enforce_event_images_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_limit INTEGER := 8;
  v_count INTEGER;
  v_raw TEXT;
BEGIN
  BEGIN
    v_raw := public.get_app_setting('event_images_limit');
    v_limit := GREATEST(1, COALESCE(NULLIF(v_raw, '')::INTEGER, 8));
  EXCEPTION WHEN OTHERS THEN
    v_limit := 8;
  END;

  SELECT COUNT(*)::INTEGER INTO v_count
  FROM public.event_images
  WHERE event_id = NEW.event_id;

  IF TG_OP = 'INSERT' AND v_count >= v_limit THEN
    RAISE EXCEPTION 'EVENT_IMAGES_LIMIT' USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS event_images_enforce_limit ON public.event_images;
CREATE TRIGGER event_images_enforce_limit
  BEFORE INSERT ON public.event_images
  FOR EACH ROW
  EXECUTE PROCEDURE public.enforce_event_images_limit();

NOTIFY pgrst, 'reload schema';
