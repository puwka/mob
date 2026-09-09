-- ============================================================
-- Clan positions (deputy/officer + trainer) + city chat mute
-- + tighten moderator admin permissions
-- ============================================================

-- ---------- Clan roles: add trainer ----------
ALTER TABLE public.clan_members
  DROP CONSTRAINT IF EXISTS clan_members_role_check;

ALTER TABLE public.clan_members
  ADD CONSTRAINT clan_members_role_check
  CHECK (role IN ('leader', 'officer', 'trainer', 'member'));

-- Leader assigns clan positions
CREATE OR REPLACE FUNCTION public.set_clan_member_role(
  p_user_id UUID,
  p_role TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_clan UUID;
  v_my_role TEXT;
  v_target_role TEXT;
  v_role TEXT := lower(btrim(COALESCE(p_role, '')));
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF v_role NOT IN ('officer', 'trainer', 'member') THEN
    RAISE EXCEPTION 'INVALID_CLAN_ROLE' USING ERRCODE = 'P0001';
  END IF;

  IF p_user_id = v_uid THEN
    RAISE EXCEPTION 'NOT_ALLOWED' USING ERRCODE = '42501';
  END IF;

  SELECT clan_id, role INTO v_clan, v_my_role
  FROM public.clan_members
  WHERE user_id = v_uid;

  IF v_clan IS NULL OR v_my_role <> 'leader' THEN
    RAISE EXCEPTION 'NOT_ALLOWED' USING ERRCODE = '42501';
  END IF;

  SELECT role INTO v_target_role
  FROM public.clan_members
  WHERE clan_id = v_clan AND user_id = p_user_id;

  IF v_target_role IS NULL THEN
    RAISE EXCEPTION 'NOT_MEMBER' USING ERRCODE = 'P0002';
  END IF;

  IF v_target_role = 'leader' THEN
    RAISE EXCEPTION 'NOT_ALLOWED' USING ERRCODE = '42501';
  END IF;

  UPDATE public.clan_members
  SET role = v_role
  WHERE clan_id = v_clan AND user_id = p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.set_clan_member_role(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_clan_member_role(UUID, TEXT) TO authenticated;

-- Kick: officer can kick member/trainer; cannot kick officer/leader
CREATE OR REPLACE FUNCTION public.kick_clan_member(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_clan UUID;
  v_my_role TEXT;
  v_target_role TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF p_user_id = v_uid THEN
    RAISE EXCEPTION 'USE_LEAVE' USING ERRCODE = 'P0001';
  END IF;

  SELECT clan_id, role INTO v_clan, v_my_role
  FROM public.clan_members WHERE user_id = v_uid;

  IF v_clan IS NULL OR v_my_role NOT IN ('leader', 'officer') THEN
    RAISE EXCEPTION 'NOT_ALLOWED' USING ERRCODE = '42501';
  END IF;

  SELECT role INTO v_target_role
  FROM public.clan_members
  WHERE clan_id = v_clan AND user_id = p_user_id;

  IF v_target_role IS NULL THEN
    RAISE EXCEPTION 'NOT_MEMBER' USING ERRCODE = 'P0002';
  END IF;

  IF v_target_role = 'leader' THEN
    RAISE EXCEPTION 'NOT_ALLOWED' USING ERRCODE = '42501';
  END IF;

  IF v_my_role = 'officer' AND v_target_role IN ('officer', 'leader') THEN
    RAISE EXCEPTION 'NOT_ALLOWED' USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.clan_members WHERE clan_id = v_clan AND user_id = p_user_id;
END;
$$;

-- Officers chat includes trainer
CREATE OR REPLACE FUNCTION public.open_clan_officers_chat(p_clan_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_role TEXT;
  v_name TEXT;
  v_id UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT cm.role, c.name INTO v_role, v_name
  FROM public.clan_members cm
  JOIN public.clans c ON c.id = cm.clan_id
  WHERE cm.clan_id = p_clan_id AND cm.user_id = v_uid;

  IF v_role IS NULL THEN
    RAISE EXCEPTION 'NOT_IN_CLAN' USING ERRCODE = 'P0001';
  END IF;

  IF v_role NOT IN ('leader', 'officer', 'trainer') THEN
    RAISE EXCEPTION 'NOT_ALLOWED' USING ERRCODE = '42501';
  END IF;

  SELECT id INTO v_id
  FROM public.conversations
  WHERE type = 'clan'
    AND clan_id = p_clan_id
    AND clan_channel = 'officers'
  LIMIT 1;

  IF v_id IS NULL THEN
    INSERT INTO public.conversations (type, title, clan_id, clan_channel)
    VALUES ('clan', v_name || ' Руководство', p_clan_id, 'officers')
    RETURNING id INTO v_id;
  END IF;

  INSERT INTO public.conversation_members (conversation_id, user_id, role)
  SELECT v_id, cm.user_id, 'member'
  FROM public.clan_members cm
  WHERE cm.clan_id = p_clan_id
    AND cm.role IN ('leader', 'officer', 'trainer')
  ON CONFLICT DO NOTHING;

  INSERT INTO public.conversation_members (conversation_id, user_id, role)
  VALUES (v_id, v_uid, 'member')
  ON CONFLICT DO NOTHING;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_clan_member_chat_channels()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_general UUID;
  v_officers UUID;
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT id INTO v_general
    FROM public.conversations
    WHERE type = 'clan'
      AND clan_id = NEW.clan_id
      AND clan_channel = 'general'
    LIMIT 1;

    IF v_general IS NOT NULL THEN
      INSERT INTO public.conversation_members (conversation_id, user_id, role)
      VALUES (v_general, NEW.user_id, 'member')
      ON CONFLICT DO NOTHING;
    END IF;

    IF NEW.role IN ('leader', 'officer', 'trainer') THEN
      SELECT id INTO v_officers
      FROM public.conversations
      WHERE type = 'clan'
        AND clan_id = NEW.clan_id
        AND clan_channel = 'officers'
      LIMIT 1;

      IF v_officers IS NOT NULL THEN
        INSERT INTO public.conversation_members (conversation_id, user_id, role)
        VALUES (v_officers, NEW.user_id, 'member')
        ON CONFLICT DO NOTHING;
      END IF;
    END IF;

    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    SELECT id INTO v_officers
    FROM public.conversations
    WHERE type = 'clan'
      AND clan_id = NEW.clan_id
      AND clan_channel = 'officers'
    LIMIT 1;

    IF v_officers IS NOT NULL THEN
      IF NEW.role IN ('leader', 'officer', 'trainer') THEN
        INSERT INTO public.conversation_members (conversation_id, user_id, role)
        VALUES (v_officers, NEW.user_id, 'member')
        ON CONFLICT DO NOTHING;
      ELSE
        DELETE FROM public.conversation_members
        WHERE conversation_id = v_officers AND user_id = NEW.user_id;
      END IF;
    END IF;

    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$;

-- ---------- City chat mutes ----------
CREATE TABLE IF NOT EXISTS public.chat_mutes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.conversations (id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  muted_by UUID REFERENCES public.profiles (id) ON DELETE SET NULL,
  reason TEXT,
  muted_until TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (conversation_id, user_id),
  CONSTRAINT chat_mutes_reason_len CHECK (
    reason IS NULL OR char_length(reason) <= 300
  )
);

CREATE INDEX IF NOT EXISTS chat_mutes_user_idx ON public.chat_mutes (user_id);
CREATE INDEX IF NOT EXISTS chat_mutes_conv_idx ON public.chat_mutes (conversation_id);

ALTER TABLE public.chat_mutes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Chat mutes readable by members" ON public.chat_mutes;
CREATE POLICY "Chat mutes readable by members"
  ON public.chat_mutes
  FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_conversation_member(conversation_id)
    OR public.admin_has_perm('dialogs')
  );

CREATE OR REPLACE FUNCTION public.is_chat_muted(
  p_conversation_id UUID,
  p_user_id UUID DEFAULT auth.uid()
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.chat_mutes m
    WHERE m.conversation_id = p_conversation_id
      AND m.user_id = p_user_id
      AND (m.muted_until IS NULL OR m.muted_until > NOW())
  );
$$;

REVOKE ALL ON FUNCTION public.is_chat_muted(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_chat_muted(UUID, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_chat_mute(p_conversation_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_row public.chat_mutes;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_row
  FROM public.chat_mutes
  WHERE conversation_id = p_conversation_id
    AND user_id = v_uid
    AND (muted_until IS NULL OR muted_until > NOW());

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object(
    'conversation_id', v_row.conversation_id,
    'muted_until', v_row.muted_until,
    'reason', v_row.reason,
    'created_at', v_row.created_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_chat_mute(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_chat_mute(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_mute_city_user(
  p_conversation_id UUID,
  p_user_id UUID,
  p_minutes INTEGER DEFAULT 60,
  p_reason TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_type TEXT;
  v_until TIMESTAMPTZ;
  v_id UUID;
  v_reason TEXT := NULLIF(btrim(COALESCE(p_reason, '')), '');
BEGIN
  v_admin := public.require_perm('dialogs');

  SELECT type INTO v_type
  FROM public.conversations
  WHERE id = p_conversation_id;

  IF v_type IS NULL THEN
    RAISE EXCEPTION 'CONVERSATION_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_type <> 'city' THEN
    RAISE EXCEPTION 'MUTE_CITY_ONLY' USING ERRCODE = 'P0001';
  END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_USER' USING ERRCODE = 'P0001';
  END IF;

  IF p_minutes IS NULL OR p_minutes < 1 THEN
    v_until := NULL; -- indefinite
  ELSE
    v_until := NOW() + make_interval(mins => LEAST(p_minutes, 60 * 24 * 30));
  END IF;

  INSERT INTO public.chat_mutes (
    conversation_id, user_id, muted_by, reason, muted_until
  )
  VALUES (
    p_conversation_id, p_user_id, v_admin, v_reason, v_until
  )
  ON CONFLICT (conversation_id, user_id) DO UPDATE SET
    muted_by = EXCLUDED.muted_by,
    reason = EXCLUDED.reason,
    muted_until = EXCLUDED.muted_until,
    created_at = NOW()
  RETURNING id INTO v_id;

  PERFORM public.write_admin_audit(
    v_admin,
    'mute_city_user',
    'chat_mute',
    v_id::TEXT,
    NULL,
    jsonb_build_object(
      'conversation_id', p_conversation_id,
      'user_id', p_user_id,
      'muted_until', v_until,
      'reason', v_reason
    )
  );

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_mute_city_user(UUID, UUID, INTEGER, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_mute_city_user(UUID, UUID, INTEGER, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_unmute_city_user(
  p_conversation_id UUID,
  p_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_old public.chat_mutes;
BEGIN
  v_admin := public.require_perm('dialogs');

  SELECT * INTO v_old
  FROM public.chat_mutes
  WHERE conversation_id = p_conversation_id AND user_id = p_user_id;

  DELETE FROM public.chat_mutes
  WHERE conversation_id = p_conversation_id AND user_id = p_user_id;

  IF FOUND THEN
    PERFORM public.write_admin_audit(
      v_admin,
      'unmute_city_user',
      'chat_mute',
      COALESCE(v_old.id::TEXT, p_user_id::TEXT),
      to_jsonb(v_old),
      NULL
    );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_unmute_city_user(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_unmute_city_user(UUID, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_list_conversation_mutes(p_conversation_id UUID)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  nickname TEXT,
  muted_until TIMESTAMPTZ,
  reason TEXT,
  created_at TIMESTAMPTZ
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
    m.user_id,
    p.nickname,
    m.muted_until,
    m.reason,
    m.created_at
  FROM public.chat_mutes m
  JOIN public.profiles p ON p.id = m.user_id
  WHERE m.conversation_id = p_conversation_id
    AND (m.muted_until IS NULL OR m.muted_until > NOW())
  ORDER BY m.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_conversation_mutes(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_conversation_mutes(UUID) TO authenticated;

-- Enforce mute in send_chat_message
CREATE OR REPLACE FUNCTION public.send_chat_message(
  p_conversation_id UUID,
  p_text TEXT DEFAULT NULL,
  p_message_type TEXT DEFAULT 'text',
  p_audio_url TEXT DEFAULT NULL,
  p_audio_duration_ms INTEGER DEFAULT NULL
)
RETURNS public.messages
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_type TEXT := COALESCE(NULLIF(trim(p_message_type), ''), 'text');
  v_text TEXT := COALESCE(trim(p_text), '');
  v_audio TEXT := NULLIF(trim(p_audio_url), '');
  v_recent INTEGER;
  v_row public.messages;
  v_other UUID;
  v_conv_type TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF v_type NOT IN ('text', 'voice') THEN
    RAISE EXCEPTION 'INVALID_MESSAGE_TYPE' USING ERRCODE = 'P0001';
  END IF;

  IF NOT public.is_conversation_member(p_conversation_id) THEN
    RAISE EXCEPTION 'NOT_MEMBER' USING ERRCODE = '42501';
  END IF;

  IF public.is_chat_muted(p_conversation_id, v_uid) THEN
    RAISE EXCEPTION 'CHAT_MUTED' USING ERRCODE = 'P0001';
  END IF;

  SELECT c.type INTO v_conv_type
  FROM public.conversations c
  WHERE c.id = p_conversation_id;

  IF v_conv_type IN ('user', 'dating', 'market') THEN
    SELECT cm.user_id INTO v_other
    FROM public.conversation_members cm
    WHERE cm.conversation_id = p_conversation_id
      AND cm.user_id <> v_uid
    LIMIT 1;

    IF v_other IS NOT NULL AND public.is_users_blocked(v_uid, v_other) THEN
      RAISE EXCEPTION 'USER_BLOCKED' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  IF v_type = 'text' THEN
    IF v_text IS NULL OR char_length(v_text) = 0 THEN
      RAISE EXCEPTION 'EMPTY_MESSAGE' USING ERRCODE = 'P0001';
    END IF;
    IF char_length(v_text) > 4000 THEN
      RAISE EXCEPTION 'MESSAGE_TOO_LONG' USING ERRCODE = 'P0001';
    END IF;
    v_audio := NULL;
  ELSE
    IF v_audio IS NULL THEN
      RAISE EXCEPTION 'EMPTY_AUDIO' USING ERRCODE = 'P0001';
    END IF;
    IF p_audio_duration_ms IS NOT NULL
       AND (p_audio_duration_ms < 500 OR p_audio_duration_ms > 120000) THEN
      RAISE EXCEPTION 'INVALID_AUDIO_DURATION' USING ERRCODE = 'P0001';
    END IF;
    v_text := '';
  END IF;

  SELECT COUNT(*)::INTEGER INTO v_recent
  FROM public.messages
  WHERE sender_id = v_uid
    AND created_at > NOW() - INTERVAL '20 seconds';

  IF v_recent >= 8 THEN
    RAISE EXCEPTION 'FLOOD' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.messages (
    conversation_id,
    sender_id,
    text,
    message_type,
    audio_url,
    audio_duration_ms
  )
  VALUES (
    p_conversation_id,
    v_uid,
    v_text,
    v_type,
    v_audio,
    CASE WHEN v_type = 'voice' THEN p_audio_duration_ms ELSE NULL END
  )
  RETURNING * INTO v_row;

  UPDATE public.conversations
  SET updated_at = NOW()
  WHERE id = p_conversation_id;

  UPDATE public.conversation_members
  SET last_read_at = NOW()
  WHERE conversation_id = p_conversation_id AND user_id = v_uid;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.send_chat_message(UUID, TEXT, TEXT, TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.send_chat_message(UUID, TEXT, TEXT, TEXT, INTEGER) TO authenticated;

-- ---------- Moderator: only moderation + city dialogs (+ dashboard/logs) ----------
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
      'dashboard', 'moderation', 'dialogs', 'logs'
    ]);
  END IF;

  RETURN FALSE;
END;
$$;

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
    -- moderator
    RETURN ARRAY[
      'dashboard', 'moderation', 'dialogs', 'logs'
    ];
  END IF;
END;
$$;

-- Moderators see only city chats
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
  v_role TEXT;
  v_type TEXT := NULLIF(trim(COALESCE(p_type, '')), '');
BEGIN
  PERFORM public.require_perm('dialogs');

  SELECT role INTO v_role FROM public.admin_users WHERE id = auth.uid();
  IF v_role = 'moderator' THEN
    v_type := 'city';
  END IF;

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
  WHERE (v_type IS NULL OR c.type = v_type)
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

NOTIFY pgrst, 'reload schema';

-- Allow trainer in admin clan member assignment
CREATE OR REPLACE FUNCTION public.admin_add_clan_member(
  p_clan_id UUID,
  p_user_id UUID,
  p_role TEXT DEFAULT 'member'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_role TEXT := COALESCE(NULLIF(p_role, ''), 'member');
BEGIN
  v_admin := public.require_admin('moderator');
  IF v_role NOT IN ('leader', 'officer', 'trainer', 'member') THEN
    RAISE EXCEPTION 'INVALID_ROLE' USING ERRCODE = 'P0001';
  END IF;

  DELETE FROM public.clan_members WHERE user_id = p_user_id AND clan_id <> p_clan_id;

  INSERT INTO public.clan_members (clan_id, user_id, role)
  VALUES (p_clan_id, p_user_id, v_role)
  ON CONFLICT (clan_id, user_id) DO UPDATE SET role = EXCLUDED.role;

  IF v_role = 'leader' THEN
    UPDATE public.clans SET leader_id = p_user_id WHERE id = p_clan_id;
    UPDATE public.clan_members
    SET role = 'member'
    WHERE clan_id = p_clan_id AND user_id <> p_user_id AND role = 'leader';
  END IF;

  PERFORM public.recompute_clan_rating(p_clan_id);
  PERFORM public.write_admin_audit(
    v_admin, 'add_clan_member', 'clan', p_clan_id::TEXT,
    NULL, jsonb_build_object('user_id', p_user_id, 'role', v_role)
  );
END;
$$;
