-- ============================================================
-- Clan chat channels: general + officers (leadership)
-- ============================================================

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS clan_channel TEXT;

UPDATE public.conversations
SET clan_channel = 'general'
WHERE type = 'clan' AND clan_channel IS NULL;

ALTER TABLE public.conversations
  DROP CONSTRAINT IF EXISTS conversations_clan_channel_chk;

ALTER TABLE public.conversations
  ADD CONSTRAINT conversations_clan_channel_chk
  CHECK (
    (type <> 'clan' AND clan_channel IS NULL)
    OR (type = 'clan' AND clan_channel IN ('general', 'officers'))
  );

DROP INDEX IF EXISTS public.conversations_clan_unique_idx;

CREATE UNIQUE INDEX IF NOT EXISTS conversations_clan_channel_unique_idx
  ON public.conversations (clan_id, clan_channel)
  WHERE type = 'clan' AND clan_id IS NOT NULL;

-- ============================================================
-- open_clan_chat → general channel
-- ============================================================

CREATE OR REPLACE FUNCTION public.open_clan_chat(p_clan_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_name TEXT;
  v_conv UUID;
  r RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.clan_members
    WHERE clan_id = p_clan_id AND user_id = v_uid
  ) THEN
    RAISE EXCEPTION 'NOT_CLAN_MEMBER' USING ERRCODE = '42501';
  END IF;

  SELECT name INTO v_name FROM public.clans WHERE id = p_clan_id;

  SELECT id INTO v_conv
  FROM public.conversations
  WHERE type = 'clan'
    AND clan_id = p_clan_id
    AND clan_channel = 'general'
  LIMIT 1;

  IF v_conv IS NULL THEN
    INSERT INTO public.conversations (type, title, clan_id, clan_channel)
    VALUES ('clan', v_name, p_clan_id, 'general')
    RETURNING id INTO v_conv;
  ELSE
    UPDATE public.conversations
    SET title = COALESCE(v_name, title)
    WHERE id = v_conv;
  END IF;

  FOR r IN
    SELECT user_id FROM public.clan_members WHERE clan_id = p_clan_id
  LOOP
    INSERT INTO public.conversation_members (conversation_id, user_id, role)
    VALUES (v_conv, r.user_id, 'member')
    ON CONFLICT DO NOTHING;
  END LOOP;

  RETURN v_conv;
END;
$$;

REVOKE ALL ON FUNCTION public.open_clan_chat(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.open_clan_chat(UUID) TO authenticated;

-- ============================================================
-- open_clan_officers_chat → leadership only
-- ============================================================

CREATE OR REPLACE FUNCTION public.open_clan_officers_chat(p_clan_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_name TEXT;
  v_role TEXT;
  v_conv UUID;
  r RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT role INTO v_role
  FROM public.clan_members
  WHERE clan_id = p_clan_id AND user_id = v_uid;

  IF v_role IS NULL THEN
    RAISE EXCEPTION 'NOT_CLAN_MEMBER' USING ERRCODE = '42501';
  END IF;

  IF v_role NOT IN ('leader', 'officer') THEN
    RAISE EXCEPTION 'NOT_CLAN_OFFICER' USING ERRCODE = '42501';
  END IF;

  SELECT name INTO v_name FROM public.clans WHERE id = p_clan_id;

  SELECT id INTO v_conv
  FROM public.conversations
  WHERE type = 'clan'
    AND clan_id = p_clan_id
    AND clan_channel = 'officers'
  LIMIT 1;

  IF v_conv IS NULL THEN
    INSERT INTO public.conversations (type, title, clan_id, clan_channel)
    VALUES ('clan', v_name || ' Руководство', p_clan_id, 'officers')
    RETURNING id INTO v_conv;
  ELSE
    UPDATE public.conversations
    SET title = COALESCE(v_name || ' Руководство', title)
    WHERE id = v_conv;
  END IF;

  FOR r IN
    SELECT user_id
    FROM public.clan_members
    WHERE clan_id = p_clan_id
      AND role IN ('leader', 'officer')
  LOOP
    INSERT INTO public.conversation_members (conversation_id, user_id, role)
    VALUES (v_conv, r.user_id, 'member')
    ON CONFLICT DO NOTHING;
  END LOOP;

  DELETE FROM public.conversation_members cm
  WHERE cm.conversation_id = v_conv
    AND NOT EXISTS (
      SELECT 1
      FROM public.clan_members m
      WHERE m.clan_id = p_clan_id
        AND m.user_id = cm.user_id
        AND m.role IN ('leader', 'officer')
    );

  RETURN v_conv;
END;
$$;

REVOKE ALL ON FUNCTION public.open_clan_officers_chat(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.open_clan_officers_chat(UUID) TO authenticated;

-- ============================================================
-- Member sync: general + officers (role-aware)
-- ============================================================

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

    IF NEW.role IN ('leader', 'officer') THEN
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
      IF NEW.role IN ('leader', 'officer') THEN
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

-- Ensure create_clan seeds general channel (preserve existing validation)
CREATE OR REPLACE FUNCTION public.create_clan(
  p_name TEXT,
  p_tag TEXT,
  p_description TEXT DEFAULT '',
  p_avatar_url TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_name TEXT := trim(p_name);
  v_tag TEXT := UPPER(trim(p_tag));
  v_desc TEXT := COALESCE(trim(p_description), '');
  v_clan UUID;
  v_conv UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF v_name IS NULL OR char_length(v_name) < 2 OR char_length(v_name) > 40 THEN
    RAISE EXCEPTION 'INVALID_NAME' USING ERRCODE = 'P0001';
  END IF;

  IF v_tag IS NULL OR char_length(v_tag) < 2 OR char_length(v_tag) > 6 THEN
    RAISE EXCEPTION 'INVALID_TAG' USING ERRCODE = 'P0001';
  END IF;

  IF v_tag !~ '^[A-Z0-9А-ЯЁ]+$' THEN
    RAISE EXCEPTION 'INVALID_TAG' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (SELECT 1 FROM public.clan_members WHERE user_id = v_uid) THEN
    RAISE EXCEPTION 'ALREADY_IN_CLAN' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (SELECT 1 FROM public.clans WHERE LOWER(name) = LOWER(v_name)) THEN
    RAISE EXCEPTION 'NAME_TAKEN' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (SELECT 1 FROM public.clans WHERE UPPER(tag) = v_tag) THEN
    RAISE EXCEPTION 'TAG_TAKEN' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.clans (name, tag, description, avatar_url, leader_id)
  VALUES (v_name, v_tag, v_desc, p_avatar_url, v_uid)
  RETURNING id INTO v_clan;

  INSERT INTO public.clan_members (clan_id, user_id, role)
  VALUES (v_clan, v_uid, 'leader');

  SELECT id INTO v_conv
  FROM public.conversations
  WHERE type = 'clan' AND clan_id = v_clan AND clan_channel = 'general';

  IF v_conv IS NULL THEN
    INSERT INTO public.conversations (type, title, clan_id, clan_channel)
    VALUES ('clan', v_name, v_clan, 'general');
  END IF;

  PERFORM public.recompute_clan_rating(v_clan);
  RETURN v_clan;
END;
$$;

REVOKE ALL ON FUNCTION public.create_clan(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_clan(TEXT, TEXT, TEXT, TEXT) TO authenticated;
