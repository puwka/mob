-- Officers (Руководство) chat: leadership only; purge fighters; sync trigger includes trainer.

-- One-shot: remove anyone who is not leadership from officers chats
DELETE FROM public.conversation_members cm
USING public.conversations c
WHERE c.id = cm.conversation_id
  AND c.type = 'clan'
  AND c.clan_channel = 'officers'
  AND NOT EXISTS (
    SELECT 1
    FROM public.clan_members m
    WHERE m.clan_id = c.clan_id
      AND m.user_id = cm.user_id
      AND m.role IN ('leader', 'officer', 'trainer')
  );

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
    RAISE EXCEPTION 'NOT_CLAN_OFFICER' USING ERRCODE = '42501';
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
  ELSE
    UPDATE public.conversations
    SET title = COALESCE(v_name || ' Руководство', title)
    WHERE id = v_id;
  END IF;

  INSERT INTO public.conversation_members (conversation_id, user_id, role)
  SELECT v_id, cm.user_id, 'member'
  FROM public.clan_members cm
  WHERE cm.clan_id = p_clan_id
    AND cm.role IN ('leader', 'officer', 'trainer')
  ON CONFLICT DO NOTHING;

  DELETE FROM public.conversation_members cm
  WHERE cm.conversation_id = v_id
    AND NOT EXISTS (
      SELECT 1
      FROM public.clan_members m
      WHERE m.clan_id = p_clan_id
        AND m.user_id = cm.user_id
        AND m.role IN ('leader', 'officer', 'trainer')
    );

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.open_clan_officers_chat(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.open_clan_officers_chat(UUID) TO authenticated;

-- Trigger function: general for all; officers only for leadership; purge on demote/leave
CREATE OR REPLACE FUNCTION public.sync_clan_conversation_member()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_general UUID;
  v_officers UUID;
  v_name TEXT;
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT name INTO v_name FROM public.clans WHERE id = NEW.clan_id;

    SELECT id INTO v_general
    FROM public.conversations
    WHERE type = 'clan'
      AND clan_id = NEW.clan_id
      AND clan_channel = 'general'
    LIMIT 1;

    IF v_general IS NULL THEN
      INSERT INTO public.conversations (type, title, clan_id, clan_channel)
      VALUES ('clan', COALESCE(v_name, 'Клан'), NEW.clan_id, 'general')
      RETURNING id INTO v_general;
    END IF;

    INSERT INTO public.conversation_members (conversation_id, user_id, role)
    VALUES (v_general, NEW.user_id, 'member')
    ON CONFLICT DO NOTHING;

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
  ELSIF TG_OP = 'UPDATE' THEN
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
  ELSIF TG_OP = 'DELETE' THEN
    DELETE FROM public.conversation_members cm
    USING public.conversations c
    WHERE cm.conversation_id = c.id
      AND c.type = 'clan'
      AND c.clan_id = OLD.clan_id
      AND cm.user_id = OLD.user_id;

    RETURN OLD;
  END IF;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS clan_members_sync_chat ON public.clan_members;
CREATE TRIGGER clan_members_sync_chat
  AFTER INSERT OR DELETE OR UPDATE OF role ON public.clan_members
  FOR EACH ROW
  EXECUTE PROCEDURE public.sync_clan_conversation_member();
