-- ============================================================
-- Admin Stage 3 (final): dialogs, economy, settings,
-- attendance, notifications, RBAC, global search
-- ============================================================

-- 1) Conversations moderation fields
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS status TEXT;

UPDATE public.conversations
SET status = 'active'
WHERE status IS NULL OR status NOT IN ('active', 'blocked', 'archived');

ALTER TABLE public.conversations
  ALTER COLUMN status SET DEFAULT 'active',
  ALTER COLUMN status SET NOT NULL;

ALTER TABLE public.conversations DROP CONSTRAINT IF EXISTS conversations_status_check;
ALTER TABLE public.conversations
  ADD CONSTRAINT conversations_status_check
  CHECK (status IN ('active', 'blocked', 'archived'));

CREATE INDEX IF NOT EXISTS conversations_status_idx
  ON public.conversations (status);
CREATE INDEX IF NOT EXISTS conversations_type_idx
  ON public.conversations (type);

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS deleted_by UUID REFERENCES public.admin_users (id) ON DELETE SET NULL;

-- 2) App settings seed (mobile reads these — no hardcode)
INSERT INTO public.app_settings (key, value) VALUES
  ('organizer_attendance_reward', '100'),
  ('event_creation_fee', '0'),
  ('withdrawal_fee', '0'),
  ('profile_photos_limit', '4'),
  ('listing_images_limit', '8'),
  ('message_max_length', '4000'),
  ('listing_default_status', 'pending'),
  ('moderation_required', 'true'),
  ('event_default_max_participants', '20')
ON CONFLICT (key) DO NOTHING;

-- 3) Notifications (structure; push delivery is a separate service)
CREATE TABLE IF NOT EXISTS public.admin_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  type TEXT NOT NULL
    CHECK (type IN (
      'all_users', 'organizers', 'city_users', 'event_participants', 'clan_members'
    )),
  target_city TEXT,
  target_event_id UUID REFERENCES public.events (id) ON DELETE SET NULL,
  target_clan_id UUID REFERENCES public.clans (id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'queued', 'sent', 'failed')),
  created_by UUID REFERENCES public.admin_users (id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sent_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS admin_notifications_created_idx
  ON public.admin_notifications (created_at DESC);

ALTER TABLE public.admin_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins read notifications" ON public.admin_notifications;
CREATE POLICY "Admins read notifications"
  ON public.admin_notifications FOR SELECT TO authenticated
  USING (public.is_admin());

-- 4) RBAC helper
CREATE OR REPLACE FUNCTION public.admin_has_perm(p_perm TEXT)
RETURNS BOOLEAN
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
    RETURN FALSE;
  END IF;

  IF v_role = 'super_admin' THEN
    RETURN TRUE;
  END IF;

  IF v_role = 'admin' THEN
    RETURN p_perm = ANY (ARRAY[
      'dashboard', 'users', 'organizers', 'events', 'clans', 'ranking',
      'market', 'moderation', 'dialogs', 'achievements', 'dictionaries',
      'economy_view', 'attendance', 'settings_view', 'notifications',
      'logs', 'search'
    ]);
  END IF;

  IF v_role = 'moderator' THEN
    RETURN p_perm = ANY (ARRAY[
      'dashboard', 'market', 'moderation', 'dialogs', 'logs', 'search'
    ]);
  END IF;

  RETURN FALSE;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_has_perm(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_has_perm(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.require_perm(p_perm TEXT)
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;
  IF NOT public.admin_has_perm(p_perm) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;
  RETURN v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.require_perm(TEXT) FROM PUBLIC;

-- Balance adjust: SUPER ADMIN only
CREATE OR REPLACE FUNCTION public.admin_adjust_organizer_balance(
  p_organizer_id UUID,
  p_amount NUMERIC,
  p_reason TEXT DEFAULT 'manual_adjustment'
)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_balance NUMERIC;
  v_old NUMERIC;
BEGIN
  v_admin := public.require_admin('super_admin');
  IF NOT public.admin_has_perm('economy_adjust') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF p_amount = 0 THEN
    RAISE EXCEPTION 'INVALID_AMOUNT' USING ERRCODE = 'P0001';
  END IF;

  PERFORM public.ensure_organizer_wallet(p_organizer_id);

  SELECT balance INTO v_old
  FROM public.organizer_wallets
  WHERE organizer_id = p_organizer_id
  FOR UPDATE;

  v_balance := v_old + p_amount;
  IF v_balance < 0 THEN
    RAISE EXCEPTION 'INSUFFICIENT_BALANCE' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.organizer_wallets
  SET balance = v_balance, updated_at = NOW()
  WHERE organizer_id = p_organizer_id;

  INSERT INTO public.organizer_transactions (
    organizer_id, amount, type, description
  ) VALUES (
    p_organizer_id,
    p_amount,
    'manual_adjustment',
    COALESCE(p_reason, 'manual_adjustment') || ' [admin:' || v_admin::TEXT || ']'
  );

  PERFORM public.write_admin_audit(
    v_admin,
    'adjust_balance',
    'organizer_wallet',
    p_organizer_id::TEXT,
    jsonb_build_object('balance', v_old),
    jsonb_build_object('balance', v_balance, 'amount', p_amount, 'reason', p_reason)
  );

  RETURN v_balance;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_adjust_organizer_balance(UUID, NUMERIC, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_adjust_organizer_balance(UUID, NUMERIC, TEXT) TO authenticated;

-- 5) Settings RPCs
CREATE OR REPLACE FUNCTION public.admin_list_settings()
RETURNS SETOF public.app_settings
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.require_perm('settings_view');
  RETURN QUERY SELECT * FROM public.app_settings ORDER BY key;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_settings() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_settings() TO authenticated;

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
  IF NOT public.admin_has_perm('economy_adjust') AND p_key LIKE '%reward%' THEN
    -- super_admin already passed
    NULL;
  END IF;

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

REVOKE ALL ON FUNCTION public.admin_upsert_setting(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_upsert_setting(TEXT, TEXT) TO authenticated;

-- Public read helper for mobile (active settings)
CREATE OR REPLACE FUNCTION public.get_app_setting(p_key TEXT)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT value FROM public.app_settings WHERE key = p_key LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.get_app_setting(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_app_setting(TEXT) TO anon, authenticated;

-- 6) Dialogs
DROP POLICY IF EXISTS "Admins read conversations" ON public.conversations;
CREATE POLICY "Admins read conversations"
  ON public.conversations FOR SELECT TO authenticated
  USING (public.admin_has_perm('dialogs'));

DROP POLICY IF EXISTS "Admins read conversation members" ON public.conversation_members;
CREATE POLICY "Admins read conversation members"
  ON public.conversation_members FOR SELECT TO authenticated
  USING (public.admin_has_perm('dialogs'));

DROP POLICY IF EXISTS "Admins read messages" ON public.messages;
CREATE POLICY "Admins read messages"
  ON public.messages FOR SELECT TO authenticated
  USING (public.admin_has_perm('dialogs'));

CREATE OR REPLACE FUNCTION public.admin_list_conversations(
  p_type TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_search TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  type TEXT,
  title TEXT,
  status TEXT,
  listing_id UUID,
  clan_id UUID,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  members_count BIGINT,
  messages_count BIGINT,
  unread_approx BIGINT,
  last_message TEXT,
  last_message_at TIMESTAMPTZ,
  member_names TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
  v_offset INTEGER := GREATEST(COALESCE(p_offset, 0), 0);
  v_q TEXT := NULLIF(lower(trim(COALESCE(p_search, ''))), '');
BEGIN
  PERFORM public.require_perm('dialogs');

  RETURN QUERY
  SELECT
    c.id,
    c.type,
    c.title,
    c.status,
    c.listing_id,
    c.clan_id,
    c.created_at,
    c.updated_at,
    (SELECT COUNT(*) FROM public.conversation_members cm WHERE cm.conversation_id = c.id),
    (SELECT COUNT(*) FROM public.messages m WHERE m.conversation_id = c.id AND m.deleted_at IS NULL),
    (
      SELECT COUNT(*) FROM public.messages m
      WHERE m.conversation_id = c.id
        AND m.deleted_at IS NULL
        AND m.created_at > COALESCE(
          (SELECT MIN(cm2.last_read_at) FROM public.conversation_members cm2
           WHERE cm2.conversation_id = c.id),
          '1970-01-01'::timestamptz
        )
    ),
    (
      SELECT CASE WHEN m.deleted_at IS NOT NULL THEN '[удалено]' ELSE left(m.text, 120) END
      FROM public.messages m
      WHERE m.conversation_id = c.id
      ORDER BY m.created_at DESC
      LIMIT 1
    ),
    (
      SELECT m.created_at FROM public.messages m
      WHERE m.conversation_id = c.id
      ORDER BY m.created_at DESC
      LIMIT 1
    ),
    (
      SELECT string_agg(p.nickname, ', ' ORDER BY p.nickname)
      FROM public.conversation_members cm
      JOIN public.profiles p ON p.id = cm.user_id
      WHERE cm.conversation_id = c.id
    )
  FROM public.conversations c
  WHERE (p_type IS NULL OR c.type = p_type)
    AND (p_status IS NULL OR c.status = p_status)
    AND (
      v_q IS NULL
      OR lower(COALESCE(c.title, '')) LIKE '%' || v_q || '%'
      OR EXISTS (
        SELECT 1 FROM public.conversation_members cm
        JOIN public.profiles p ON p.id = cm.user_id
        WHERE cm.conversation_id = c.id AND lower(p.nickname) LIKE '%' || v_q || '%'
      )
    )
  ORDER BY COALESCE(
    (SELECT m.created_at FROM public.messages m WHERE m.conversation_id = c.id ORDER BY m.created_at DESC LIMIT 1),
    c.updated_at
  ) DESC
  LIMIT v_limit OFFSET v_offset;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_conversations(TEXT, TEXT, TEXT, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_conversations(TEXT, TEXT, TEXT, INTEGER, INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_list_messages(p_conversation_id UUID)
RETURNS TABLE (
  id UUID,
  sender_id UUID,
  sender_nickname TEXT,
  text TEXT,
  created_at TIMESTAMPTZ,
  edited_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.require_perm('dialogs');
  RETURN QUERY
  SELECT
    m.id,
    m.sender_id,
    p.nickname,
    m.text,
    m.created_at,
    m.edited_at,
    m.deleted_at,
    m.deleted_by
  FROM public.messages m
  LEFT JOIN public.profiles p ON p.id = m.sender_id
  WHERE m.conversation_id = p_conversation_id
  ORDER BY m.created_at ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_messages(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_messages(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_soft_delete_message(p_message_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_old public.messages;
BEGIN
  v_admin := public.require_perm('dialogs');
  SELECT * INTO v_old FROM public.messages WHERE id = p_message_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.messages
  SET deleted_at = NOW(), deleted_by = v_admin
  WHERE id = p_message_id;

  PERFORM public.write_admin_audit(
    v_admin, 'soft_delete_message', 'message', p_message_id::TEXT,
    jsonb_build_object('text', v_old.text, 'deleted_at', v_old.deleted_at),
    jsonb_build_object('deleted_at', NOW())
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_soft_delete_message(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_soft_delete_message(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_conversation_status(
  p_id UUID,
  p_status TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_old TEXT;
BEGIN
  v_admin := public.require_perm('dialogs');
  IF p_status NOT IN ('active', 'blocked', 'archived') THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING ERRCODE = 'P0001';
  END IF;

  SELECT status INTO v_old FROM public.conversations WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.conversations SET status = p_status, updated_at = NOW() WHERE id = p_id;

  PERFORM public.write_admin_audit(
    v_admin, 'set_conversation_status', 'conversation', p_id::TEXT,
    jsonb_build_object('status', v_old),
    jsonb_build_object('status', p_status)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_conversation_status(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_conversation_status(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_delete_conversation(p_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_old public.conversations;
BEGIN
  v_admin := public.require_admin('admin');
  IF NOT public.admin_has_perm('dialogs') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_old FROM public.conversations WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  DELETE FROM public.conversations WHERE id = p_id;

  PERFORM public.write_admin_audit(
    v_admin, 'delete_conversation', 'conversation', p_id::TEXT, to_jsonb(v_old), NULL
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_conversation(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_conversation(UUID) TO authenticated;
