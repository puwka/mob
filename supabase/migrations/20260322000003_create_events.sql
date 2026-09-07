-- ============================================================
-- Events + participants
-- ============================================================

CREATE TABLE IF NOT EXISTS public.events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  city TEXT NOT NULL,
  location TEXT NOT NULL,
  event_date TIMESTAMPTZ NOT NULL,
  organizer_id UUID REFERENCES public.profiles (id) ON DELETE SET NULL,
  max_participants INTEGER NOT NULL CHECK (max_participants > 0),
  image_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS events_city_idx ON public.events (city);
CREATE INDEX IF NOT EXISTS events_event_date_idx ON public.events (event_date);
CREATE INDEX IF NOT EXISTS events_city_date_idx ON public.events (city, event_date);

CREATE TABLE IF NOT EXISTS public.event_participants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES public.events (id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (event_id, user_id)
);

CREATE INDEX IF NOT EXISTS event_participants_event_idx
  ON public.event_participants (event_id);
CREATE INDEX IF NOT EXISTS event_participants_user_idx
  ON public.event_participants (user_id);

-- RLS
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_participants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Events readable by authenticated"
  ON public.events;
CREATE POLICY "Events readable by authenticated"
  ON public.events
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Participants readable by authenticated"
  ON public.event_participants;
CREATE POLICY "Participants readable by authenticated"
  ON public.event_participants
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Users can join events"
  ON public.event_participants;
CREATE POLICY "Users can join events"
  ON public.event_participants
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can leave events"
  ON public.event_participants;
CREATE POLICY "Users can leave events"
  ON public.event_participants
  FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- Safe join with capacity lock (prevents overbooking races)
CREATE OR REPLACE FUNCTION public.join_event(p_event_id UUID)
RETURNS public.event_participants
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_max INTEGER;
  v_count INTEGER;
  v_row public.event_participants;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT max_participants
  INTO v_max
  FROM public.events
  WHERE id = p_event_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  -- Already joined?
  SELECT * INTO v_row
  FROM public.event_participants
  WHERE event_id = p_event_id AND user_id = v_uid;

  IF FOUND THEN
    RETURN v_row;
  END IF;

  SELECT COUNT(*)::INTEGER INTO v_count
  FROM public.event_participants
  WHERE event_id = p_event_id;

  IF v_count >= v_max THEN
    RAISE EXCEPTION 'NO_SLOTS' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.event_participants (event_id, user_id)
  VALUES (p_event_id, v_uid)
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.join_event(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.join_event(UUID) TO authenticated;

-- Realtime (ignore if already added)
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.event_participants;
  EXCEPTION
    WHEN duplicate_object THEN NULL;
    WHEN undefined_object THEN NULL;
  END;
END $$;
