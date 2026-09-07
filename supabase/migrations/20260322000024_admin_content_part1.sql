-- ============================================================
-- Admin Stage 2: content management RPCs, cities, storage,
-- listing rejection_reason, achievement is_active
-- ============================================================

-- 1) Reference: cities
CREATE TABLE IF NOT EXISTS public.app_cities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS app_cities_active_sort_idx
  ON public.app_cities (is_active, sort_order, name);

ALTER TABLE public.app_cities ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated read cities" ON public.app_cities;
CREATE POLICY "Authenticated read cities"
  ON public.app_cities
  FOR SELECT
  TO authenticated
  USING (is_active = TRUE OR public.is_admin());

INSERT INTO public.app_cities (name, sort_order)
VALUES
  ('Москва', 1),
  ('Краснодар', 2),
  ('Санкт-Петербург', 3)
ON CONFLICT (name) DO NOTHING;

-- 2) Listing rejection reason + achievement active flag
ALTER TABLE public.listings
  ADD COLUMN IF NOT EXISTS rejection_reason TEXT;

ALTER TABLE public.achievements
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS achievements_active_idx
  ON public.achievements (is_active);

-- Allow admin to change seller_id / views freely
CREATE OR REPLACE FUNCTION public.protect_listing_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NOT public.is_admin() THEN
    NEW.seller_id = OLD.seller_id;
    IF NEW.views_count IS DISTINCT FROM OLD.views_count
       AND NEW.views_count <> OLD.views_count + 1 THEN
      NEW.views_count = OLD.views_count;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- 3) Storage buckets for admin/content
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('event-images', 'event-images', true, 8388608, ARRAY['image/jpeg', 'image/png', 'image/webp']),
  ('clan-images', 'clan-images', true, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp']),
  ('achievement-icons', 'achievement-icons', true, 2097152, ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/svg+xml'])
ON CONFLICT (id) DO UPDATE
SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Public read for new buckets
DROP POLICY IF EXISTS "Event images public read" ON storage.objects;
CREATE POLICY "Event images public read"
  ON storage.objects FOR SELECT
  USING (bucket_id IN ('event-images', 'clan-images', 'achievement-icons'));

-- Admins manage all content buckets (incl. avatars / listing-images)
DROP POLICY IF EXISTS "Admins manage storage objects" ON storage.objects;
CREATE POLICY "Admins manage storage objects"
  ON storage.objects
  FOR ALL
  TO authenticated
  USING (
    public.is_admin()
    AND bucket_id IN (
      'avatars', 'listing-images', 'event-images', 'clan-images', 'achievement-icons'
    )
  )
  WITH CHECK (
    public.is_admin()
    AND bucket_id IN (
      'avatars', 'listing-images', 'event-images', 'clan-images', 'achievement-icons'
    )
  );

-- Organizers upload own event images
DROP POLICY IF EXISTS "Organizers upload event images" ON storage.objects;
CREATE POLICY "Organizers upload event images"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'event-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "Organizers update event images" ON storage.objects;
CREATE POLICY "Organizers update event images"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'event-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "Organizers delete event images" ON storage.objects;
CREATE POLICY "Organizers delete event images"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'event-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Clan leaders: clan-images/{user_id}/...
DROP POLICY IF EXISTS "Users upload clan images" ON storage.objects;
CREATE POLICY "Users upload clan images"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'clan-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "Users update clan images" ON storage.objects;
CREATE POLICY "Users update clan images"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'clan-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "Users delete clan images" ON storage.objects;
CREATE POLICY "Users delete clan images"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'clan-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- 4) Shared: confirm attendance + reward for a given organizer
CREATE OR REPLACE FUNCTION public._award_attendance_reward(
  p_event public.events,
  p_part public.event_participants,
  p_user public.profiles,
  p_confirmed_by UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_wallet public.organizer_wallets%ROWTYPE;
  v_reward NUMERIC(14, 2);
  v_setting TEXT;
  v_organizer UUID := p_event.organizer_id;
BEGIN
  IF v_organizer IS NULL THEN
    RAISE EXCEPTION 'NO_ORGANIZER' USING ERRCODE = 'P0001';
  END IF;

  SELECT value INTO v_setting
  FROM public.app_settings
  WHERE key = 'organizer_attendance_reward';

  v_reward := COALESCE(NULLIF(v_setting, '')::NUMERIC, 100);
  IF v_reward < 0 THEN
    v_reward := 0;
  END IF;

  UPDATE public.event_participants
  SET
    attendance_status = 'confirmed',
    attended_at = NOW(),
    confirmed_by = p_confirmed_by
  WHERE id = p_part.id
    AND attendance_status = 'not_confirmed'
  RETURNING * INTO p_part;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ALREADY_CONFIRMED' USING ERRCODE = 'P0001';
  END IF;

  v_wallet := public.ensure_organizer_wallet(v_organizer);

  INSERT INTO public.organizer_transactions (
    organizer_id, event_id, participant_id, amount, type, description
  )
  VALUES (
    v_organizer,
    p_event.id,
    p_part.id,
    v_reward,
    'attendance_reward',
    'Подтверждение: ' || p_user.nickname || ' · ' || p_event.title
  );

  UPDATE public.organizer_wallets
  SET balance = balance + v_reward
  WHERE organizer_id = v_organizer
  RETURNING * INTO v_wallet;

  RETURN jsonb_build_object(
    'participant_id', p_part.id,
    'user_id', p_user.id,
    'nickname', p_user.nickname,
    'city', p_user.city,
    'avatar_url', p_user.avatar_url,
    'event_id', p_event.id,
    'event_title', p_event.title,
    'attended_at', p_part.attended_at,
    'reward_amount', v_reward,
    'balance', v_wallet.balance,
    'currency', v_wallet.currency
  );
END;
$$;

REVOKE ALL ON FUNCTION public._award_attendance_reward(
  public.events, public.event_participants, public.profiles, UUID
) FROM PUBLIC;

-- Rewrite confirm_event_attendance to use shared helper
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

  SELECT * INTO v_event FROM public.events WHERE id = p_event_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_event.organizer_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'NOT_EVENT_OWNER' USING ERRCODE = '42501';
  END IF;

  IF v_event.status <> 'active' THEN
    IF v_event.status = 'finished' THEN
      RAISE EXCEPTION 'EVENT_FINISHED' USING ERRCODE = 'P0001';
    ELSIF v_event.status = 'cancelled' THEN
      RAISE EXCEPTION 'EVENT_CANCELLED' USING ERRCODE = 'P0001';
    ELSE
      RAISE EXCEPTION 'EVENT_NOT_ACTIVE' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  SELECT * INTO v_user FROM public.profiles WHERE public_qr_id = p_public_qr_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_part
  FROM public.event_participants
  WHERE event_id = p_event_id AND user_id = v_user.id
  FOR UPDATE;

  IF NOT FOUND OR v_part.registration_status <> 'registered' THEN
    RAISE EXCEPTION 'NOT_REGISTERED' USING ERRCODE = 'P0001';
  END IF;

  IF v_part.attendance_status = 'confirmed' THEN
    RAISE EXCEPTION 'ALREADY_CONFIRMED' USING ERRCODE = 'P0001';
  END IF;

  RETURN public._award_attendance_reward(v_event, v_part, v_user, v_uid);
END;
$$;

-- ===================== EVENTS =====================

CREATE OR REPLACE FUNCTION public.admin_list_events(
  p_city TEXT DEFAULT NULL,
  p_organizer_id UUID DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_date_from TIMESTAMPTZ DEFAULT NULL,
  p_date_to TIMESTAMPTZ DEFAULT NULL,
  p_search TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  title TEXT,
  city TEXT,
  event_date TIMESTAMPTZ,
  status TEXT,
  max_participants INTEGER,
  participants_count BIGINT,
  organizer_id UUID,
  organizer_nickname TEXT,
  image_url TEXT,
  location TEXT,
  description TEXT,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_q TEXT := NULLIF(lower(trim(COALESCE(p_search, ''))), '');
  v_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
  v_offset INTEGER := GREATEST(COALESCE(p_offset, 0), 0);
BEGIN
  PERFORM public.require_admin('moderator');

  RETURN QUERY
  SELECT
    e.id,
    e.title,
    e.city,
    e.event_date,
    e.status,
    e.max_participants,
    (
      SELECT COUNT(*) FROM public.event_participants ep
      WHERE ep.event_id = e.id AND ep.registration_status = 'registered'
    ),
    e.organizer_id,
    op.nickname,
    e.image_url,
    e.location,
    e.description,
    e.created_at
  FROM public.events e
  LEFT JOIN public.profiles op ON op.id = e.organizer_id
  WHERE (p_city IS NULL OR e.city = p_city)
    AND (p_organizer_id IS NULL OR e.organizer_id = p_organizer_id)
    AND (p_status IS NULL OR e.status = p_status)
    AND (p_date_from IS NULL OR e.event_date >= p_date_from)
    AND (p_date_to IS NULL OR e.event_date <= p_date_to)
    AND (v_q IS NULL OR lower(e.title) LIKE '%' || v_q || '%')
  ORDER BY e.event_date DESC
  LIMIT v_limit OFFSET v_offset;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_events(
  TEXT, UUID, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, INTEGER, INTEGER
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_events(
  TEXT, UUID, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, INTEGER, INTEGER
) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_upsert_event(
  p_id UUID DEFAULT NULL,
  p_title TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_city TEXT DEFAULT NULL,
  p_location TEXT DEFAULT NULL,
  p_event_date TIMESTAMPTZ DEFAULT NULL,
  p_organizer_id UUID DEFAULT NULL,
  p_max_participants INTEGER DEFAULT NULL,
  p_image_url TEXT DEFAULT NULL,
  p_clear_image BOOLEAN DEFAULT FALSE,
  p_status TEXT DEFAULT NULL
)
RETURNS public.events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_old public.events;
  v_new public.events;
BEGIN
  v_admin := public.require_admin('moderator');

  IF p_id IS NULL THEN
    IF p_title IS NULL OR p_city IS NULL OR p_location IS NULL
       OR p_event_date IS NULL OR p_organizer_id IS NULL
       OR p_max_participants IS NULL THEN
      RAISE EXCEPTION 'MISSING_FIELDS' USING ERRCODE = 'P0001';
    END IF;
    IF p_status IS NOT NULL AND p_status NOT IN ('draft', 'active', 'finished', 'cancelled') THEN
      RAISE EXCEPTION 'INVALID_STATUS' USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO public.events (
      title, description, city, location, event_date,
      organizer_id, max_participants, image_url, status
    ) VALUES (
      trim(p_title),
      COALESCE(p_description, ''),
      trim(p_city),
      trim(p_location),
      p_event_date,
      p_organizer_id,
      p_max_participants,
      CASE WHEN p_clear_image THEN NULL ELSE p_image_url END,
      COALESCE(p_status, 'active')
    )
    RETURNING * INTO v_new;

    PERFORM public.write_admin_audit(
      v_admin, 'create_event', 'event', v_new.id::TEXT, NULL, to_jsonb(v_new)
    );
    RETURN v_new;
  END IF;

  SELECT * INTO v_old FROM public.events WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF p_status IS NOT NULL AND p_status NOT IN ('draft', 'active', 'finished', 'cancelled') THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.events SET
    title = COALESCE(NULLIF(trim(p_title), ''), title),
    description = COALESCE(p_description, description),
    city = COALESCE(NULLIF(trim(p_city), ''), city),
    location = COALESCE(NULLIF(trim(p_location), ''), location),
    event_date = COALESCE(p_event_date, event_date),
    organizer_id = COALESCE(p_organizer_id, organizer_id),
    max_participants = COALESCE(p_max_participants, max_participants),
    image_url = CASE
      WHEN p_clear_image THEN NULL
      WHEN p_image_url IS NOT NULL THEN p_image_url
      ELSE image_url
    END,
    status = COALESCE(p_status, status),
    updated_at = NOW()
  WHERE id = p_id
  RETURNING * INTO v_new;

  PERFORM public.write_admin_audit(
    v_admin, 'update_event', 'event', p_id::TEXT, to_jsonb(v_old), to_jsonb(v_new)
  );
  RETURN v_new;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_upsert_event(
  UUID, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, UUID, INTEGER, TEXT, BOOLEAN, TEXT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_upsert_event(
  UUID, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, UUID, INTEGER, TEXT, BOOLEAN, TEXT
) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_delete_event(p_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_old public.events;
BEGIN
  v_admin := public.require_admin('admin');
  SELECT * INTO v_old FROM public.events WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;
  DELETE FROM public.events WHERE id = p_id;
  PERFORM public.write_admin_audit(
    v_admin, 'delete_event', 'event', p_id::TEXT, to_jsonb(v_old), NULL
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_event(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_event(UUID) TO authenticated;

-- Participants
CREATE OR REPLACE FUNCTION public.admin_list_event_participants(p_event_id UUID)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  nickname TEXT,
  avatar_url TEXT,
  city TEXT,
  registration_status TEXT,
  attendance_status TEXT,
  registered_at TIMESTAMPTZ,
  attended_at TIMESTAMPTZ,
  confirmed_by UUID,
  confirmed_by_nickname TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.require_admin('moderator');
  RETURN QUERY
  SELECT
    ep.id,
    ep.user_id,
    p.nickname,
    p.avatar_url,
    p.city,
    ep.registration_status,
    ep.attendance_status,
    ep.registered_at,
    ep.attended_at,
    ep.confirmed_by,
    cb.nickname
  FROM public.event_participants ep
  JOIN public.profiles p ON p.id = ep.user_id
  LEFT JOIN public.profiles cb ON cb.id = ep.confirmed_by
  WHERE ep.event_id = p_event_id
  ORDER BY ep.registered_at DESC NULLS LAST, ep.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_event_participants(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_event_participants(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_register_participant(
  p_event_id UUID,
  p_user_id UUID
)
RETURNS public.event_participants
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_event public.events;
  v_count INTEGER;
  v_row public.event_participants;
BEGIN
  v_admin := public.require_admin('moderator');

  SELECT * INTO v_event FROM public.events WHERE id = p_event_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  SELECT COUNT(*)::INTEGER INTO v_count
  FROM public.event_participants
  WHERE event_id = p_event_id AND registration_status = 'registered';

  SELECT * INTO v_row
  FROM public.event_participants
  WHERE event_id = p_event_id AND user_id = p_user_id
  FOR UPDATE;

  IF FOUND THEN
    IF v_row.registration_status = 'registered' THEN
      RAISE EXCEPTION 'ALREADY_REGISTERED' USING ERRCODE = 'P0001';
    END IF;
    IF v_count >= v_event.max_participants THEN
      RAISE EXCEPTION 'EVENT_FULL' USING ERRCODE = 'P0001';
    END IF;
    UPDATE public.event_participants SET
      registration_status = 'registered',
      attendance_status = 'not_confirmed',
      registered_at = NOW(),
      attended_at = NULL,
      confirmed_by = NULL
    WHERE id = v_row.id
    RETURNING * INTO v_row;
  ELSE
    IF v_count >= v_event.max_participants THEN
      RAISE EXCEPTION 'EVENT_FULL' USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO public.event_participants (
      event_id, user_id, registration_status, attendance_status, registered_at
    ) VALUES (
      p_event_id, p_user_id, 'registered', 'not_confirmed', NOW()
    )
    RETURNING * INTO v_row;
  END IF;

  PERFORM public.write_admin_audit(
    v_admin, 'register_participant', 'event_participant', v_row.id::TEXT,
    NULL, to_jsonb(v_row)
  );
  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_register_participant(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_register_participant(UUID, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_cancel_participant(p_participant_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_old public.event_participants;
BEGIN
  v_admin := public.require_admin('moderator');
  SELECT * INTO v_old FROM public.event_participants WHERE id = p_participant_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;
  UPDATE public.event_participants
  SET registration_status = 'cancelled'
  WHERE id = p_participant_id;
  PERFORM public.write_admin_audit(
    v_admin, 'cancel_participant', 'event_participant', p_participant_id::TEXT,
    to_jsonb(v_old), jsonb_build_object('registration_status', 'cancelled')
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_cancel_participant(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_cancel_participant(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_remove_participant(p_participant_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_old public.event_participants;
BEGIN
  v_admin := public.require_admin('admin');
  SELECT * INTO v_old FROM public.event_participants WHERE id = p_participant_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;
  DELETE FROM public.event_participants WHERE id = p_participant_id;
  PERFORM public.write_admin_audit(
    v_admin, 'remove_participant', 'event_participant', p_participant_id::TEXT,
    to_jsonb(v_old), NULL
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_remove_participant(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_remove_participant(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_confirm_participant(
  p_participant_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_part public.event_participants%ROWTYPE;
  v_event public.events%ROWTYPE;
  v_user public.profiles%ROWTYPE;
  v_result JSONB;
BEGIN
  v_admin := public.require_admin('moderator');

  SELECT * INTO v_part FROM public.event_participants WHERE id = p_participant_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;
  IF v_part.registration_status <> 'registered' THEN
    RAISE EXCEPTION 'NOT_REGISTERED' USING ERRCODE = 'P0001';
  END IF;
  IF v_part.attendance_status = 'confirmed' THEN
    RAISE EXCEPTION 'ALREADY_CONFIRMED' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_event FROM public.events WHERE id = v_part.event_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_user FROM public.profiles WHERE id = v_part.user_id;

  v_result := public._award_attendance_reward(v_event, v_part, v_user, v_admin);

  PERFORM public.write_admin_audit(
    v_admin, 'confirm_attendance', 'event_participant', p_participant_id::TEXT,
    NULL, v_result
  );
  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_confirm_participant(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_confirm_participant(UUID) TO authenticated;
