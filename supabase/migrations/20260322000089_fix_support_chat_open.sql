-- ============================================================
-- Fix support chat open: moderators must get a personal ticket.
-- is_admin() is true for moderator/admin/super_admin; only
-- admin/super_admin use the staff inbox (no personal ticket).
-- ============================================================

CREATE OR REPLACE FUNCTION public.is_support_staff()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.admin_users
    WHERE admin_users.id = auth.uid()
      AND admin_users.role IN ('super_admin', 'admin')
  );
$$;

REVOKE ALL ON FUNCTION public.is_support_staff() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_support_staff() TO authenticated;

CREATE OR REPLACE FUNCTION public.is_conversation_member(p_conversation_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.conversation_members
    WHERE conversation_id = p_conversation_id
      AND user_id = auth.uid()
  )
  OR (
    public.is_support_staff()
    AND EXISTS (
      SELECT 1
      FROM public.conversations c
      WHERE c.id = p_conversation_id
        AND c.type = 'support'
    )
  );
$$;

CREATE OR REPLACE FUNCTION public.trg_support_chat_write_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type TEXT;
  v_support UUID := public.support_user_id();
BEGIN
  SELECT c.type INTO v_type
  FROM public.conversations c
  WHERE c.id = NEW.conversation_id;

  IF v_type IS DISTINCT FROM 'support' THEN
    RETURN NEW;
  END IF;

  IF v_support IS NULL THEN
    RAISE EXCEPTION 'SUPPORT_NOT_CONFIGURED' USING ERRCODE = 'P0001';
  END IF;

  IF NEW.sender_id = v_support THEN
    RETURN NEW;
  END IF;

  -- Ticket owner may write questions
  IF EXISTS (
    SELECT 1
    FROM public.conversations c
    WHERE c.id = NEW.conversation_id
      AND c.support_requester_id = NEW.sender_id
  ) THEN
    RETURN NEW;
  END IF;

  -- Only admin / super_admin may reply as staff
  IF public.is_support_staff() THEN
    INSERT INTO public.conversation_members (conversation_id, user_id, role, last_read_at)
    VALUES (NEW.conversation_id, NEW.sender_id, 'member', NOW())
    ON CONFLICT (conversation_id, user_id) DO NOTHING;
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'SUPPORT_REPLY_FORBIDDEN' USING ERRCODE = '42501';
END;
$$;

CREATE OR REPLACE FUNCTION public.ensure_admin_support_inbox()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL OR NOT public.is_support_staff() THEN
    RETURN;
  END IF;

  INSERT INTO public.conversation_members (conversation_id, user_id, role, last_read_at)
  SELECT c.id, v_uid, 'member', NOW()
  FROM public.conversations c
  WHERE c.type = 'support'
  ON CONFLICT (conversation_id, user_id) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION public.open_support_chat()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_support UUID := public.support_user_id();
  v_conv UUID;
  v_created BOOLEAN := FALSE;
  v_admin UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF v_support IS NULL THEN
    RAISE EXCEPTION 'SUPPORT_NOT_CONFIGURED' USING ERRCODE = 'P0001';
  END IF;

  IF v_uid = v_support THEN
    RAISE EXCEPTION 'CANNOT_CHAT_SELF' USING ERRCODE = 'P0001';
  END IF;

  -- Staff inbox only for admin/super_admin (not moderators)
  IF public.is_support_staff() THEN
    PERFORM public.ensure_admin_support_inbox();
    SELECT c.id INTO v_conv
    FROM public.conversations c
    JOIN public.conversation_members cm ON cm.conversation_id = c.id
    WHERE c.type = 'support'
      AND cm.user_id = v_uid
    ORDER BY c.updated_at DESC
    LIMIT 1;
    RETURN v_conv; -- may be null if no tickets yet
  END IF;

  SELECT c.id INTO v_conv
  FROM public.conversations c
  JOIN public.conversation_members cm_me
    ON cm_me.conversation_id = c.id AND cm_me.user_id = v_uid
  JOIN public.conversation_members cm_bot
    ON cm_bot.conversation_id = c.id AND cm_bot.user_id = v_support
  WHERE c.type = 'support'
    AND (
      c.support_requester_id = v_uid
      OR c.support_requester_id IS NULL
    )
  LIMIT 1;

  IF v_conv IS NULL THEN
    INSERT INTO public.conversations (type, title, support_requester_id)
    VALUES ('support', 'Поддержка', v_uid)
    RETURNING id INTO v_conv;
    v_created := TRUE;

    INSERT INTO public.conversation_members (conversation_id, user_id, role, last_read_at)
    VALUES
      (v_conv, v_uid, 'member', NOW()),
      (v_conv, v_support, 'owner', NOW())
    ON CONFLICT DO NOTHING;

    FOR v_admin IN
      SELECT id FROM public.admin_users
      WHERE role IN ('super_admin', 'admin')
    LOOP
      INSERT INTO public.conversation_members (conversation_id, user_id, role, last_read_at)
      VALUES (v_conv, v_admin, 'member', NOW())
      ON CONFLICT DO NOTHING;
    END LOOP;
  ELSE
    UPDATE public.conversation_members
    SET hidden_at = NULL
    WHERE conversation_id = v_conv
      AND user_id = v_uid
      AND hidden_at IS NOT NULL;

    UPDATE public.conversations
    SET support_requester_id = COALESCE(support_requester_id, v_uid)
    WHERE id = v_conv;
  END IF;

  IF v_created THEN
    INSERT INTO public.messages (
      conversation_id,
      sender_id,
      text,
      message_type
    )
    VALUES (
      v_conv,
      v_support,
      'Здравствуйте! Вы написали в поддержку «Мой Страйкбол». '
      || 'Опишите вопрос — администратор ответит как можно скорее.',
      'text'
    );

    UPDATE public.conversations
    SET updated_at = NOW()
    WHERE id = v_conv;
  END IF;

  RETURN v_conv;
END;
$$;

CREATE OR REPLACE FUNCTION public.conversation_unread_by_type()
RETURNS TABLE (
  type TEXT,
  unread_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.auto_finish_past_events();

  IF public.is_support_staff() THEN
    PERFORM public.ensure_admin_support_inbox();
  END IF;

  RETURN QUERY
  WITH unread AS (
    SELECT c.type, COUNT(*)::BIGINT AS unread_count
    FROM public.messages m
    JOIN public.conversations c ON c.id = m.conversation_id
    JOIN public.conversation_members cm
      ON cm.conversation_id = c.id AND cm.user_id = auth.uid()
    WHERE m.sender_id <> auth.uid()
      AND m.deleted_at IS NULL
      AND cm.hidden_at IS NULL
      AND (cm.last_read_at IS NULL OR m.created_at > cm.last_read_at)
    GROUP BY c.type
  )
  SELECT t.type, COALESCE(u.unread_count, 0)::BIGINT
  FROM (
    VALUES
      ('market'), ('clan'), ('user'), ('city'),
      ('dating'), ('event'), ('support')
  ) AS t(type)
  LEFT JOIN unread u ON u.type = t.type;
END;
$$;

NOTIFY pgrst, 'reload schema';
