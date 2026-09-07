-- ============================================================
-- Events v2: status, attendance, confirm-by-QR RPCs
-- ============================================================

-- 1) Events: status + updated_at
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS status TEXT,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

UPDATE public.events
SET status = 'active'
WHERE status IS NULL OR status = '';

ALTER TABLE public.events
  ALTER COLUMN status SET DEFAULT 'active',
  ALTER COLUMN status SET NOT NULL;

ALTER TABLE public.events DROP CONSTRAINT IF EXISTS events_status_check;
ALTER TABLE public.events
  ADD CONSTRAINT events_status_check
  CHECK (status IN ('draft', 'active', 'finished', 'cancelled'));

CREATE INDEX IF NOT EXISTS events_status_idx ON public.events (status);
CREATE INDEX IF NOT EXISTS events_organizer_idx ON public.events (organizer_id);

CREATE OR REPLACE FUNCTION public.set_events_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS events_set_updated_at ON public.events;
CREATE TRIGGER events_set_updated_at
  BEFORE UPDATE ON public.events
  FOR EACH ROW
  EXECUTE PROCEDURE public.set_events_updated_at();

-- 2) Participants: registration + attendance
ALTER TABLE public.event_participants
  ADD COLUMN IF NOT EXISTS registration_status TEXT,
  ADD COLUMN IF NOT EXISTS attendance_status TEXT,
  ADD COLUMN IF NOT EXISTS registered_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS attended_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS confirmed_by UUID REFERENCES public.profiles (id) ON DELETE SET NULL;

UPDATE public.event_participants
SET
  registration_status = COALESCE(NULLIF(registration_status, ''), 'registered'),
  attendance_status = COALESCE(NULLIF(attendance_status, ''), 'not_confirmed'),
  registered_at = COALESCE(registered_at, created_at, NOW())
WHERE TRUE;

ALTER TABLE public.event_participants
  ALTER COLUMN registration_status SET DEFAULT 'registered',
  ALTER COLUMN registration_status SET NOT NULL,
  ALTER COLUMN attendance_status SET DEFAULT 'not_confirmed',
  ALTER COLUMN attendance_status SET NOT NULL,
  ALTER COLUMN registered_at SET DEFAULT NOW();

ALTER TABLE public.event_participants
  DROP CONSTRAINT IF EXISTS event_participants_registration_status_check;
ALTER TABLE public.event_participants
  ADD CONSTRAINT event_participants_registration_status_check
  CHECK (registration_status IN ('registered', 'cancelled'));

ALTER TABLE public.event_participants
  DROP CONSTRAINT IF EXISTS event_participants_attendance_status_check;
ALTER TABLE public.event_participants
  ADD CONSTRAINT event_participants_attendance_status_check
  CHECK (attendance_status IN ('not_confirmed', 'confirmed'));

-- UNIQUE(event_id, user_id) already exists from create migration

CREATE INDEX IF NOT EXISTS event_participants_attendance_idx
  ON public.event_participants (event_id, attendance_status);

-- 3) join_event: only active events; set registration fields
CREATE OR REPLACE FUNCTION public.join_event(p_event_id UUID)
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
  v_row public.event_participants;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
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
      -- Re-join: check capacity among active registrations
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
        confirmed_by = NULL
      WHERE id = v_row.id
      RETURNING * INTO v_row;
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
    event_id, user_id, registration_status, attendance_status, registered_at
  )
  VALUES (p_event_id, v_uid, 'registered', 'not_confirmed', NOW())
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.join_event(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.join_event(UUID) TO authenticated;

-- 4) leave_event: soft-cancel registration
CREATE OR REPLACE FUNCTION public.leave_event(p_event_id UUID)
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

  UPDATE public.event_participants
  SET registration_status = 'cancelled'
  WHERE event_id = p_event_id
    AND user_id = v_uid
    AND registration_status = 'registered';
END;
$$;

REVOKE ALL ON FUNCTION public.leave_event(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.leave_event(UUID) TO authenticated;

-- 5) create_event RPC (organizer only)
CREATE OR REPLACE FUNCTION public.create_event(
  p_title TEXT,
  p_description TEXT,
  p_city TEXT,
  p_location TEXT,
  p_event_date TIMESTAMPTZ,
  p_max_participants INTEGER,
  p_image_url TEXT DEFAULT NULL,
  p_status TEXT DEFAULT 'active'
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

  INSERT INTO public.events (
    organizer_id, title, description, city, location,
    event_date, max_participants, image_url, status
  )
  VALUES (
    v_uid,
    trim(p_title),
    COALESCE(trim(p_description), ''),
    trim(p_city),
    trim(p_location),
    p_event_date,
    p_max_participants,
    p_image_url,
    v_status
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_event(TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, INTEGER, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_event(TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, INTEGER, TEXT, TEXT) TO authenticated;

-- 6) Confirm attendance by QR (atomic)
CREATE OR REPLACE FUNCTION public.confirm_event_attendance(
  p_event_id UUID,
  p_public_qr_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_event public.events%ROWTYPE;
  v_user public.profiles%ROWTYPE;
  v_part public.event_participants%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_organizer() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_event
  FROM public.events
  WHERE id = p_event_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_event.organizer_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'NOT_EVENT_OWNER' USING ERRCODE = '42501';
  END IF;

  IF v_event.status = 'finished' THEN
    RAISE EXCEPTION 'EVENT_FINISHED' USING ERRCODE = 'P0001';
  END IF;

  IF v_event.status = 'cancelled' THEN
    RAISE EXCEPTION 'EVENT_CANCELLED' USING ERRCODE = 'P0001';
  END IF;

  IF v_event.status <> 'active' THEN
    RAISE EXCEPTION 'EVENT_NOT_ACTIVE' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_user
  FROM public.profiles
  WHERE public_qr_id = p_public_qr_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_part
  FROM public.event_participants
  WHERE event_id = p_event_id
    AND user_id = v_user.id
  FOR UPDATE;

  IF NOT FOUND OR v_part.registration_status <> 'registered' THEN
    RAISE EXCEPTION 'NOT_REGISTERED' USING ERRCODE = 'P0001';
  END IF;

  IF v_part.attendance_status = 'confirmed' THEN
    RAISE EXCEPTION 'ALREADY_CONFIRMED' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.event_participants
  SET
    attendance_status = 'confirmed',
    attended_at = NOW(),
    confirmed_by = v_uid
  WHERE id = v_part.id
  RETURNING * INTO v_part;

  RETURN jsonb_build_object(
    'participant_id', v_part.id,
    'user_id', v_user.id,
    'nickname', v_user.nickname,
    'city', v_user.city,
    'avatar_url', v_user.avatar_url,
    'event_id', v_event.id,
    'event_title', v_event.title,
    'attended_at', v_part.attended_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.confirm_event_attendance(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.confirm_event_attendance(UUID, UUID) TO authenticated;

-- 7) Participants readable: all auth can read (list for organizer UI);
--    keep existing SELECT policy. Writes only via RPCs for join/leave/confirm.
REVOKE INSERT, UPDATE, DELETE ON public.event_participants FROM authenticated;
GRANT SELECT ON public.event_participants TO authenticated;

-- Storage: event covers in avatars path {uid}/event_{id}.jpg (reuse avatars bucket policies)
