-- Event participant side (light / dark)

ALTER TABLE public.event_participants
  ADD COLUMN IF NOT EXISTS side TEXT;

ALTER TABLE public.event_participants
  DROP CONSTRAINT IF EXISTS event_participants_side_check;

ALTER TABLE public.event_participants
  ADD CONSTRAINT event_participants_side_check
  CHECK (side IS NULL OR side IN ('light', 'dark'));

CREATE INDEX IF NOT EXISTS event_participants_side_idx
  ON public.event_participants (event_id, side)
  WHERE registration_status = 'registered';

DROP FUNCTION IF EXISTS public.join_event(UUID);

CREATE OR REPLACE FUNCTION public.join_event(
  p_event_id UUID,
  p_side TEXT
)
RETURNS public.event_participants
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_max INTEGER;
  v_status TEXT;
  v_count INTEGER;
  v_row public.event_participants%ROWTYPE;
  v_side TEXT := lower(btrim(COALESCE(p_side, '')));
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF v_side NOT IN ('light', 'dark') THEN
    RAISE EXCEPTION 'INVALID_SIDE' USING ERRCODE = 'P0001';
  END IF;

  SELECT max_participants, status
  INTO v_max, v_status
  FROM public.events
  WHERE id = p_event_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_status <> 'active' THEN
    RAISE EXCEPTION 'EVENT_NOT_ACTIVE' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_row
  FROM public.event_participants
  WHERE event_id = p_event_id AND user_id = v_uid;

  IF FOUND THEN
    IF v_row.registration_status = 'cancelled' THEN
      SELECT COUNT(*)::INTEGER INTO v_count
      FROM public.event_participants
      WHERE event_id = p_event_id
        AND registration_status = 'registered';

      IF v_count >= v_max THEN
        RAISE EXCEPTION 'NO_SLOTS' USING ERRCODE = 'P0001';
      END IF;

      UPDATE public.event_participants
      SET
        registration_status = 'registered',
        registered_at = NOW(),
        attendance_status = 'not_confirmed',
        attended_at = NULL,
        confirmed_by = NULL,
        side = v_side
      WHERE id = v_row.id
      RETURNING * INTO v_row;
    ELSIF v_row.registration_status = 'registered' THEN
      -- Already joined: allow updating side while not confirmed
      IF v_row.attendance_status = 'not_confirmed' AND v_row.side IS DISTINCT FROM v_side THEN
        UPDATE public.event_participants
        SET side = v_side
        WHERE id = v_row.id
        RETURNING * INTO v_row;
      END IF;
    END IF;
    RETURN v_row;
  END IF;

  SELECT COUNT(*)::INTEGER INTO v_count
  FROM public.event_participants
  WHERE event_id = p_event_id
    AND registration_status = 'registered';

  IF v_count >= v_max THEN
    RAISE EXCEPTION 'NO_SLOTS' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.event_participants (
    event_id, user_id, registration_status, attendance_status, registered_at, side
  )
  VALUES (p_event_id, v_uid, 'registered', 'not_confirmed', NOW(), v_side)
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.join_event(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.join_event(UUID, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
