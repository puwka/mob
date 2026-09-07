-- ============================================================
-- Admin Stage 3 part 2: economy, attendance, notifications, search
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_economy_stats()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today DATE := CURRENT_DATE;
  v_month_start DATE := date_trunc('month', NOW())::DATE;
BEGIN
  PERFORM public.require_perm('economy_view');

  RETURN jsonb_build_object(
    'organizers_total', (
      SELECT COUNT(*) FROM public.profiles WHERE role = 'organizer'
    ),
    'balance_total', (
      SELECT COALESCE(SUM(balance), 0) FROM public.organizer_wallets
    ),
    'awarded_total', (
      SELECT COALESCE(SUM(amount), 0) FROM public.organizer_transactions
      WHERE amount > 0
    ),
    'awarded_today', (
      SELECT COALESCE(SUM(amount), 0) FROM public.organizer_transactions
      WHERE amount > 0 AND created_at::DATE = v_today
    ),
    'awarded_month', (
      SELECT COALESCE(SUM(amount), 0) FROM public.organizer_transactions
      WHERE amount > 0 AND created_at::DATE >= v_month_start
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_economy_stats() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_economy_stats() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_economy_organizers(
  p_limit INTEGER DEFAULT 100,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  nickname TEXT,
  avatar_url TEXT,
  city TEXT,
  balance NUMERIC,
  events_count BIGINT,
  confirmed_count BIGINT,
  earned NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 100), 1), 200);
  v_offset INTEGER := GREATEST(COALESCE(p_offset, 0), 0);
BEGIN
  PERFORM public.require_perm('economy_view');

  RETURN QUERY
  SELECT
    p.id,
    p.nickname,
    p.avatar_url,
    p.city,
    COALESCE(w.balance, 0),
    (SELECT COUNT(*) FROM public.events e WHERE e.organizer_id = p.id),
    (
      SELECT COUNT(*)
      FROM public.event_participants ep
      JOIN public.events e ON e.id = ep.event_id
      WHERE e.organizer_id = p.id AND ep.attendance_status = 'confirmed'
    ),
    (
      SELECT COALESCE(SUM(t.amount), 0)
      FROM public.organizer_transactions t
      WHERE t.organizer_id = p.id AND t.amount > 0
    )
  FROM public.profiles p
  LEFT JOIN public.organizer_wallets w ON w.organizer_id = p.id
  WHERE p.role = 'organizer'
  ORDER BY COALESCE(w.balance, 0) DESC, p.nickname
  LIMIT v_limit OFFSET v_offset;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_economy_organizers(INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_economy_organizers(INTEGER, INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_list_transactions(
  p_organizer_id UUID DEFAULT NULL,
  p_type TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 100,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  created_at TIMESTAMPTZ,
  organizer_id UUID,
  organizer_nickname TEXT,
  event_id UUID,
  event_title TEXT,
  participant_id UUID,
  participant_nickname TEXT,
  type TEXT,
  amount NUMERIC,
  description TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 100), 1), 300);
  v_offset INTEGER := GREATEST(COALESCE(p_offset, 0), 0);
BEGIN
  PERFORM public.require_perm('economy_view');

  RETURN QUERY
  SELECT
    t.id,
    t.created_at,
    t.organizer_id,
    op.nickname,
    t.event_id,
    e.title,
    t.participant_id,
    pp.nickname,
    t.type,
    t.amount,
    t.description
  FROM public.organizer_transactions t
  JOIN public.profiles op ON op.id = t.organizer_id
  LEFT JOIN public.events e ON e.id = t.event_id
  LEFT JOIN public.event_participants ep ON ep.id = t.participant_id
  LEFT JOIN public.profiles pp ON pp.id = ep.user_id
  WHERE (p_organizer_id IS NULL OR t.organizer_id = p_organizer_id)
    AND (p_type IS NULL OR t.type = p_type)
  ORDER BY t.created_at DESC
  LIMIT v_limit OFFSET v_offset;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_transactions(UUID, TEXT, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_transactions(UUID, TEXT, INTEGER, INTEGER) TO authenticated;

-- Attendance / QR confirmations list
CREATE OR REPLACE FUNCTION public.admin_list_attendance(
  p_organizer_id UUID DEFAULT NULL,
  p_event_id UUID DEFAULT NULL,
  p_city TEXT DEFAULT NULL,
  p_date_from TIMESTAMPTZ DEFAULT NULL,
  p_date_to TIMESTAMPTZ DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 100,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  participant_id UUID,
  event_id UUID,
  event_title TEXT,
  event_city TEXT,
  organizer_id UUID,
  organizer_nickname TEXT,
  user_id UUID,
  user_nickname TEXT,
  public_qr_id UUID,
  registration_status TEXT,
  attendance_status TEXT,
  registered_at TIMESTAMPTZ,
  attended_at TIMESTAMPTZ,
  reward_amount NUMERIC,
  has_reward BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 100), 1), 300);
  v_offset INTEGER := GREATEST(COALESCE(p_offset, 0), 0);
BEGIN
  PERFORM public.require_perm('attendance');

  RETURN QUERY
  SELECT
    ep.id,
    e.id,
    e.title,
    e.city,
    e.organizer_id,
    op.nickname,
    ep.user_id,
    up.nickname,
    up.public_qr_id,
    ep.registration_status,
    ep.attendance_status,
    ep.registered_at,
    ep.attended_at,
    COALESCE((
      SELECT t.amount FROM public.organizer_transactions t
      WHERE t.participant_id = ep.id AND t.type = 'attendance_reward'
      LIMIT 1
    ), 0),
    EXISTS (
      SELECT 1 FROM public.organizer_transactions t
      WHERE t.participant_id = ep.id AND t.type = 'attendance_reward'
    )
  FROM public.event_participants ep
  JOIN public.events e ON e.id = ep.event_id
  JOIN public.profiles up ON up.id = ep.user_id
  LEFT JOIN public.profiles op ON op.id = e.organizer_id
  WHERE ep.registration_status = 'registered'
    AND (p_organizer_id IS NULL OR e.organizer_id = p_organizer_id)
    AND (p_event_id IS NULL OR e.id = p_event_id)
    AND (p_city IS NULL OR e.city = p_city)
    AND (p_date_from IS NULL OR COALESCE(ep.attended_at, ep.registered_at) >= p_date_from)
    AND (p_date_to IS NULL OR COALESCE(ep.attended_at, ep.registered_at) <= p_date_to)
    AND (p_status IS NULL OR ep.attendance_status = p_status)
  ORDER BY COALESCE(ep.attended_at, ep.registered_at) DESC NULLS LAST
  LIMIT v_limit OFFSET v_offset;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_attendance(
  UUID, UUID, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, INTEGER, INTEGER
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_attendance(
  UUID, UUID, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, INTEGER, INTEGER
) TO authenticated;

-- Gate confirm with attendance perm
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
  v_admin := public.require_perm('attendance');

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

-- Notifications
CREATE OR REPLACE FUNCTION public.admin_list_notifications(p_limit INTEGER DEFAULT 50)
RETURNS SETOF public.admin_notifications
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.require_perm('notifications');
  RETURN QUERY
  SELECT * FROM public.admin_notifications
  ORDER BY created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_notifications(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_notifications(INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_create_notification(
  p_title TEXT,
  p_body TEXT,
  p_type TEXT,
  p_target_city TEXT DEFAULT NULL,
  p_target_event_id UUID DEFAULT NULL,
  p_target_clan_id UUID DEFAULT NULL
)
RETURNS public.admin_notifications
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_row public.admin_notifications;
BEGIN
  v_admin := public.require_perm('notifications');

  IF p_type NOT IN (
    'all_users', 'organizers', 'city_users', 'event_participants', 'clan_members'
  ) THEN
    RAISE EXCEPTION 'INVALID_TYPE' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.admin_notifications (
    title, body, type, target_city, target_event_id, target_clan_id,
    status, created_by
  ) VALUES (
    trim(p_title),
    trim(p_body),
    p_type,
    p_target_city,
    p_target_event_id,
    p_target_clan_id,
    'queued',
    v_admin
  )
  RETURNING * INTO v_row;

  PERFORM public.write_admin_audit(
    v_admin, 'create_notification', 'notification', v_row.id::TEXT,
    NULL, to_jsonb(v_row)
  );
  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_create_notification(
  TEXT, TEXT, TEXT, TEXT, UUID, UUID
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_create_notification(
  TEXT, TEXT, TEXT, TEXT, UUID, UUID
) TO authenticated;

-- Global search
CREATE OR REPLACE FUNCTION public.admin_global_search(p_query TEXT, p_limit INTEGER DEFAULT 8)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_q TEXT := NULLIF(lower(trim(COALESCE(p_query, ''))), '');
  v_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 8), 1), 20);
BEGIN
  PERFORM public.require_perm('search');
  IF v_q IS NULL OR length(v_q) < 2 THEN
    RETURN jsonb_build_object(
      'users', '[]'::jsonb,
      'clans', '[]'::jsonb,
      'events', '[]'::jsonb,
      'listings', '[]'::jsonb
    );
  END IF;

  RETURN jsonb_build_object(
    'users', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', p.id, 'label', p.nickname, 'meta', p.city, 'kind', 'user'
      ))
      FROM (
        SELECT id, nickname, city FROM public.profiles
        WHERE lower(nickname) LIKE '%' || v_q || '%'
           OR phone LIKE '%' || v_q || '%'
        ORDER BY nickname LIMIT v_limit
      ) p
    ), '[]'::jsonb),
    'clans', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', c.id, 'label', c.name, 'meta', c.tag, 'kind', 'clan'
      ))
      FROM (
        SELECT id, name, tag FROM public.clans
        WHERE lower(name) LIKE '%' || v_q || '%'
           OR lower(tag) LIKE '%' || v_q || '%'
        ORDER BY name LIMIT v_limit
      ) c
    ), '[]'::jsonb),
    'events', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', e.id, 'label', e.title, 'meta', e.city, 'kind', 'event'
      ))
      FROM (
        SELECT id, title, city FROM public.events
        WHERE lower(title) LIKE '%' || v_q || '%'
        ORDER BY event_date DESC LIMIT v_limit
      ) e
    ), '[]'::jsonb),
    'listings', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', l.id, 'label', l.title, 'meta', l.city || ' · ' || l.status, 'kind', 'listing'
      ))
      FROM (
        SELECT id, title, city, status FROM public.listings
        WHERE lower(title) LIKE '%' || v_q || '%'
        ORDER BY created_at DESC LIMIT v_limit
      ) l
    ), '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_global_search(TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_global_search(TEXT, INTEGER) TO authenticated;

-- Expose permissions for UI
CREATE OR REPLACE FUNCTION public.admin_my_permissions()
RETURNS TEXT[]
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
BEGIN
  SELECT role INTO v_role FROM public.admin_users WHERE id = auth.uid();
  IF v_role IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF v_role = 'super_admin' THEN
    RETURN ARRAY[
      'dashboard', 'users', 'organizers', 'events', 'clans', 'ranking',
      'market', 'moderation', 'dialogs', 'achievements', 'dictionaries',
      'economy_view', 'economy_adjust', 'attendance', 'settings_view',
      'settings_write', 'notifications', 'logs', 'search'
    ];
  ELSIF v_role = 'admin' THEN
    RETURN ARRAY[
      'dashboard', 'users', 'organizers', 'events', 'clans', 'ranking',
      'market', 'moderation', 'dialogs', 'achievements', 'dictionaries',
      'economy_view', 'attendance', 'settings_view', 'notifications',
      'logs', 'search'
    ];
  ELSE
    RETURN ARRAY[
      'dashboard', 'market', 'moderation', 'dialogs', 'logs', 'search'
    ];
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_my_permissions() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_my_permissions() TO authenticated;

-- Gate settings write for super_admin via require_admin already
CREATE OR REPLACE FUNCTION public.admin_upsert_setting(
  p_key TEXT,
  p_value TEXT
)
RETURNS public.app_settings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_old public.app_settings;
  v_new public.app_settings;
BEGIN
  v_admin := public.require_admin('super_admin');

  IF NULLIF(trim(p_key), '') IS NULL THEN
    RAISE EXCEPTION 'INVALID_KEY' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_old FROM public.app_settings WHERE key = p_key;

  INSERT INTO public.app_settings (key, value, updated_at)
  VALUES (trim(p_key), COALESCE(p_value, ''), NOW())
  ON CONFLICT (key) DO UPDATE
    SET value = EXCLUDED.value, updated_at = NOW()
  RETURNING * INTO v_new;

  PERFORM public.write_admin_audit(
    v_admin, 'upsert_setting', 'app_settings', p_key,
    CASE WHEN v_old.key IS NULL THEN NULL ELSE to_jsonb(v_old) END,
    to_jsonb(v_new)
  );
  RETURN v_new;
END;
$$;

COMMENT ON FUNCTION public.admin_has_perm(TEXT) IS 'Backend RBAC for admin panel permissions';
COMMENT ON TABLE public.admin_notifications IS 'Queued system notifications; push delivery is external';
