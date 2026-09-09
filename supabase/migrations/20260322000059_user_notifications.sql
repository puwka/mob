-- ============================================================
-- In-app notifications: events + chats, with per-dialog mute
-- ============================================================

ALTER TABLE public.conversation_members
  ADD COLUMN IF NOT EXISTS notifications_muted_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS public.user_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('event_created', 'chat_message')),
  title TEXT NOT NULL,
  body TEXT NOT NULL DEFAULT '',
  event_id UUID REFERENCES public.events (id) ON DELETE CASCADE,
  conversation_id UUID REFERENCES public.conversations (id) ON DELETE CASCADE,
  actor_id UUID REFERENCES public.profiles (id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  seen_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS user_notifications_user_unseen_idx
  ON public.user_notifications (user_id, created_at DESC)
  WHERE seen_at IS NULL;

CREATE INDEX IF NOT EXISTS user_notifications_user_created_idx
  ON public.user_notifications (user_id, created_at DESC);

-- One unseen chat alert per conversation (reduce city spam)
CREATE UNIQUE INDEX IF NOT EXISTS user_notifications_chat_unseen_uniq
  ON public.user_notifications (user_id, conversation_id)
  WHERE kind = 'chat_message' AND seen_at IS NULL AND conversation_id IS NOT NULL;

ALTER TABLE public.user_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "User notifications select own" ON public.user_notifications;
CREATE POLICY "User notifications select own"
  ON public.user_notifications
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "User notifications update own" ON public.user_notifications;
CREATE POLICY "User notifications update own"
  ON public.user_notifications
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.user_notifications;
  EXCEPTION
    WHEN duplicate_object THEN NULL;
    WHEN undefined_object THEN NULL;
  END;
END $$;

-- ---------- Mute notifications for a dialog ----------
CREATE OR REPLACE FUNCTION public.set_conversation_notifications_muted(
  p_conversation_id UUID,
  p_muted BOOLEAN
)
RETURNS BOOLEAN
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

  IF NOT public.is_conversation_member(p_conversation_id) THEN
    RAISE EXCEPTION 'NOT_MEMBER' USING ERRCODE = '42501';
  END IF;

  UPDATE public.conversation_members
  SET notifications_muted_at = CASE WHEN p_muted THEN NOW() ELSE NULL END
  WHERE conversation_id = p_conversation_id
    AND user_id = v_uid;

  RETURN p_muted;
END;
$$;

REVOKE ALL ON FUNCTION public.set_conversation_notifications_muted(UUID, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_conversation_notifications_muted(UUID, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_conversation_notifications_muted(
  p_conversation_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_muted TIMESTAMPTZ;
BEGIN
  IF v_uid IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT notifications_muted_at INTO v_muted
  FROM public.conversation_members
  WHERE conversation_id = p_conversation_id
    AND user_id = v_uid;

  RETURN v_muted IS NOT NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.get_conversation_notifications_muted(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_conversation_notifications_muted(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_pending_user_notifications(
  p_limit INTEGER DEFAULT 20
)
RETURNS SETOF public.user_notifications
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);
BEGIN
  IF v_uid IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT *
  FROM public.user_notifications
  WHERE user_id = v_uid
    AND seen_at IS NULL
  ORDER BY created_at ASC
  LIMIT v_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.get_pending_user_notifications(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_pending_user_notifications(INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_user_notification_seen(p_id UUID)
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

  UPDATE public.user_notifications
  SET seen_at = NOW()
  WHERE id = p_id
    AND user_id = v_uid
    AND seen_at IS NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_user_notification_seen(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_user_notification_seen(UUID) TO authenticated;

-- ---------- Emit helpers ----------
CREATE OR REPLACE FUNCTION public.emit_chat_message_notification(
  p_conversation_id UUID,
  p_sender_id UUID,
  p_preview TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_title TEXT;
  v_preview TEXT := COALESCE(NULLIF(btrim(p_preview), ''), 'Новое сообщение');
  v_sender_nick TEXT;
  r RECORD;
BEGIN
  SELECT COALESCE(NULLIF(btrim(c.title), ''), 'Диалог') INTO v_title
  FROM public.conversations c
  WHERE c.id = p_conversation_id;

  SELECT nickname INTO v_sender_nick
  FROM public.profiles
  WHERE id = p_sender_id;

  IF v_sender_nick IS NOT NULL AND char_length(v_sender_nick) > 0 THEN
    v_title := v_sender_nick;
  END IF;

  FOR r IN
    SELECT cm.user_id
    FROM public.conversation_members cm
    WHERE cm.conversation_id = p_conversation_id
      AND cm.user_id <> p_sender_id
      AND cm.notifications_muted_at IS NULL
      AND cm.hidden_at IS NULL
  LOOP
    UPDATE public.user_notifications
    SET
      title = v_title,
      body = left(v_preview, 200),
      actor_id = p_sender_id,
      created_at = NOW(),
      seen_at = NULL
    WHERE user_id = r.user_id
      AND conversation_id = p_conversation_id
      AND kind = 'chat_message'
      AND seen_at IS NULL;

    IF NOT FOUND THEN
      BEGIN
        INSERT INTO public.user_notifications (
          user_id, kind, title, body, conversation_id, actor_id
        ) VALUES (
          r.user_id, 'chat_message', v_title, left(v_preview, 200),
          p_conversation_id, p_sender_id
        );
      EXCEPTION
        WHEN unique_violation THEN
          UPDATE public.user_notifications
          SET
            title = v_title,
            body = left(v_preview, 200),
            actor_id = p_sender_id,
            created_at = NOW()
          WHERE user_id = r.user_id
            AND conversation_id = p_conversation_id
            AND kind = 'chat_message'
            AND seen_at IS NULL;
      END;
    END IF;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.emit_event_created_notifications(
  p_event_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event public.events%ROWTYPE;
  r RECORD;
BEGIN
  SELECT * INTO v_event FROM public.events WHERE id = p_event_id;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF v_event.status <> 'active' THEN
    RETURN;
  END IF;

  FOR r IN
    SELECT p.id
    FROM public.profiles p
    WHERE p.status = 'active'
      AND lower(btrim(p.city)) = lower(btrim(v_event.city))
      AND p.id <> v_event.organizer_id
  LOOP
    INSERT INTO public.user_notifications (
      user_id, kind, title, body, event_id, actor_id
    ) VALUES (
      r.id,
      'event_created',
      'Новая игра в вашем городе',
      left(v_event.title, 120),
      v_event.id,
      v_event.organizer_id
    );
  END LOOP;
END;
$$;

-- ---------- Trigger: new message → chat notification ----------
CREATE OR REPLACE FUNCTION public.trg_notify_on_chat_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_preview TEXT;
BEGIN
  IF NEW.deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  v_preview := CASE
    WHEN NEW.message_type = 'voice' THEN 'Голосовое сообщение'
    WHEN NEW.message_type = 'image' THEN 'Фото'
    ELSE COALESCE(NULLIF(btrim(NEW.text), ''), 'Новое сообщение')
  END;

  PERFORM public.emit_chat_message_notification(
    NEW.conversation_id,
    NEW.sender_id,
    v_preview
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS messages_notify_users ON public.messages;
CREATE TRIGGER messages_notify_users
  AFTER INSERT ON public.messages
  FOR EACH ROW
  EXECUTE PROCEDURE public.trg_notify_on_chat_message();

-- ---------- Trigger: new active event → city notifications ----------
CREATE OR REPLACE FUNCTION public.trg_notify_on_event_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'active' THEN
    PERFORM public.emit_event_created_notifications(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS events_notify_city_users ON public.events;
CREATE TRIGGER events_notify_city_users
  AFTER INSERT ON public.events
  FOR EACH ROW
  EXECUTE PROCEDURE public.trg_notify_on_event_created();

-- Also when draft → active
CREATE OR REPLACE FUNCTION public.trg_notify_on_event_activated()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'active'
     AND OLD.status IS DISTINCT FROM 'active' THEN
    PERFORM public.emit_event_created_notifications(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS events_notify_on_activate ON public.events;
CREATE TRIGGER events_notify_on_activate
  AFTER UPDATE OF status ON public.events
  FOR EACH ROW
  EXECUTE PROCEDURE public.trg_notify_on_event_activated();

NOTIFY pgrst, 'reload schema';
