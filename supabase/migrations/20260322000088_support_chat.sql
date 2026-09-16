-- ============================================================
-- Support chat: type=support, open_support_chat, admin replies
-- ============================================================

-- Stable support bot account
DO $$
DECLARE
  v_id UUID := 'b1000000-0000-4000-8000-000000000001'::uuid;
  v_email TEXT := 'support@moystrykbol.local';
  v_pass TEXT;
BEGIN
  CREATE EXTENSION IF NOT EXISTS pgcrypto;
  v_pass := crypt('SupportBot!2026', gen_salt('bf'));

  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = v_id) THEN
    INSERT INTO auth.users (
      instance_id,
      id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at
    ) VALUES (
      COALESCE(
        (SELECT id FROM auth.instances LIMIT 1),
        '00000000-0000-0000-0000-000000000000'::uuid
      ),
      v_id,
      'authenticated',
      'authenticated',
      v_email,
      v_pass,
      NOW(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{"nickname":"Поддержка"}'::jsonb,
      NOW(),
      NOW()
    );
  END IF;

  INSERT INTO public.profiles (
    id, phone, nickname, city, role, created_at
  )
  VALUES (
    v_id,
    '+70000000001',
    'Поддержка',
    'Москва',
    'user',
    NOW()
  )
  ON CONFLICT (id) DO UPDATE
  SET nickname = EXCLUDED.nickname;
END;
$$;

INSERT INTO public.app_settings (key, value)
VALUES ('support_user_id', 'b1000000-0000-4000-8000-000000000001')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

CREATE OR REPLACE FUNCTION public.support_user_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT NULLIF(btrim(value), '')::UUID
  FROM public.app_settings
  WHERE key = 'support_user_id'
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.support_user_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.support_user_id() TO authenticated;

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS support_requester_id UUID
    REFERENCES public.profiles (id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS conversations_support_requester_idx
  ON public.conversations (support_requester_id)
  WHERE type = 'support';

ALTER TABLE public.conversations DROP CONSTRAINT IF EXISTS conversations_type_check;
ALTER TABLE public.conversations
  ADD CONSTRAINT conversations_type_check
  CHECK (type IN (
    'market', 'clan', 'user', 'city', 'dating', 'event', 'support'
  ));

ALTER TABLE public.conversations DROP CONSTRAINT IF EXISTS conversations_type_fields_chk;
ALTER TABLE public.conversations
  ADD CONSTRAINT conversations_type_fields_chk
  CHECK (
    (
      type = 'market'
      AND listing_id IS NOT NULL
      AND clan_id IS NULL
      AND city_name IS NULL
      AND dating_match_id IS NULL
      AND event_id IS NULL
    )
    OR (
      type = 'clan'
      AND clan_id IS NOT NULL
      AND listing_id IS NULL
      AND city_name IS NULL
      AND dating_match_id IS NULL
      AND event_id IS NULL
    )
    OR (
      type = 'user'
      AND listing_id IS NULL
      AND clan_id IS NULL
      AND city_name IS NULL
      AND dating_match_id IS NULL
      AND event_id IS NULL
    )
    OR (
      type = 'city'
      AND city_name IS NOT NULL
      AND listing_id IS NULL
      AND clan_id IS NULL
      AND dating_match_id IS NULL
      AND event_id IS NULL
      AND clan_channel IS NULL
    )
    OR (
      type = 'dating'
      AND listing_id IS NULL
      AND clan_id IS NULL
      AND city_name IS NULL
      AND clan_channel IS NULL
      AND event_id IS NULL
    )
    OR (
      type = 'event'
      AND event_id IS NOT NULL
      AND listing_id IS NULL
      AND clan_id IS NULL
      AND city_name IS NULL
      AND dating_match_id IS NULL
      AND clan_channel IS NULL
    )
    OR (
      type = 'support'
      AND listing_id IS NULL
      AND clan_id IS NULL
      AND city_name IS NULL
      AND dating_match_id IS NULL
      AND event_id IS NULL
      AND clan_channel IS NULL
    )
  );

-- Admins can read support chats without prior membership
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
    public.is_admin()
    AND EXISTS (
      SELECT 1
      FROM public.conversations c
      WHERE c.id = p_conversation_id
        AND c.type = 'support'
    )
  );
$$;

-- Restrict who may write in support chats; auto-join admins
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

  -- Welcome / system sends from bot account
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

  -- Only admins may reply as staff
  IF public.is_admin() THEN
    INSERT INTO public.conversation_members (conversation_id, user_id, role, last_read_at)
    VALUES (NEW.conversation_id, NEW.sender_id, 'member', NOW())
    ON CONFLICT (conversation_id, user_id) DO NOTHING;
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'SUPPORT_REPLY_FORBIDDEN' USING ERRCODE = '42501';
END;
$$;

DROP TRIGGER IF EXISTS messages_support_write_guard ON public.messages;
CREATE TRIGGER messages_support_write_guard
  BEFORE INSERT ON public.messages
  FOR EACH ROW
  EXECUTE PROCEDURE public.trg_support_chat_write_guard();

-- Sync current admin into all support tickets (inbox)
CREATE OR REPLACE FUNCTION public.ensure_admin_support_inbox()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL OR NOT public.is_admin() THEN
    RETURN;
  END IF;

  INSERT INTO public.conversation_members (conversation_id, user_id, role, last_read_at)
  SELECT c.id, v_uid, 'member', NOW()
  FROM public.conversations c
  WHERE c.type = 'support'
  ON CONFLICT (conversation_id, user_id) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_admin_support_inbox() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_admin_support_inbox() TO authenticated;

-- Open / create personal support ticket + welcome
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

  -- Admins don't open a personal ticket this way; sync inbox instead
  IF public.is_admin() THEN
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

    -- All current admins see the ticket
    FOR v_admin IN SELECT id FROM public.admin_users
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

REVOKE ALL ON FUNCTION public.open_support_chat() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.open_support_chat() TO authenticated;

-- Unread map includes support
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

  IF public.is_admin() THEN
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
