-- ============================================================
-- Messaging: clans (minimal), conversations, members, messages
-- ============================================================

-- Minimal clans (needed for type=clan chats)
CREATE TABLE IF NOT EXISTS public.clans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.clan_members (
  clan_id UUID NOT NULL REFERENCES public.clans (id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'member'
    CHECK (role IN ('owner', 'officer', 'member')),
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (clan_id, user_id)
);

CREATE INDEX IF NOT EXISTS clan_members_user_idx ON public.clan_members (user_id);

CREATE TABLE IF NOT EXISTS public.conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT NOT NULL CHECK (type IN ('market', 'clan', 'user')),
  title TEXT,
  listing_id UUID REFERENCES public.listings (id) ON DELETE SET NULL,
  clan_id UUID REFERENCES public.clans (id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT conversations_market_listing_chk
    CHECK (type <> 'market' OR listing_id IS NOT NULL),
  CONSTRAINT conversations_clan_chk
    CHECK (type <> 'clan' OR clan_id IS NOT NULL)
);

CREATE UNIQUE INDEX IF NOT EXISTS conversations_clan_unique_idx
  ON public.conversations (clan_id)
  WHERE type = 'clan' AND clan_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS conversations_type_idx ON public.conversations (type);
CREATE INDEX IF NOT EXISTS conversations_listing_idx ON public.conversations (listing_id);
CREATE INDEX IF NOT EXISTS conversations_updated_idx ON public.conversations (updated_at DESC);

CREATE TABLE IF NOT EXISTS public.conversation_members (
  conversation_id UUID NOT NULL REFERENCES public.conversations (id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'member'
    CHECK (role IN ('owner', 'member')),
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_read_at TIMESTAMPTZ,
  PRIMARY KEY (conversation_id, user_id)
);

CREATE INDEX IF NOT EXISTS conversation_members_user_idx
  ON public.conversation_members (user_id, conversation_id);

CREATE TABLE IF NOT EXISTS public.messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.conversations (id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  text TEXT NOT NULL CHECK (char_length(trim(text)) > 0 AND char_length(text) <= 4000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  edited_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS messages_conversation_created_idx
  ON public.messages (conversation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS messages_sender_created_idx
  ON public.messages (sender_id, created_at DESC);

-- updated_at on conversations
CREATE OR REPLACE FUNCTION public.set_conversation_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS conversations_set_updated_at ON public.conversations;
CREATE TRIGGER conversations_set_updated_at
  BEFORE UPDATE ON public.conversations
  FOR EACH ROW
  EXECUTE PROCEDURE public.set_conversation_updated_at();

-- ============================================================
-- RLS
-- ============================================================

ALTER TABLE public.clans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clan_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Clans readable by members" ON public.clans;
CREATE POLICY "Clans readable by members"
  ON public.clans FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.clan_members cm
      WHERE cm.clan_id = id AND cm.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Clan members readable by clan mates" ON public.clan_members;
CREATE POLICY "Clan members readable by clan mates"
  ON public.clan_members FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.clan_members me
      WHERE me.clan_id = clan_members.clan_id AND me.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Conversations readable by members" ON public.conversations;
CREATE POLICY "Conversations readable by members"
  ON public.conversations FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.conversation_members cm
      WHERE cm.conversation_id = id AND cm.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Conversation members readable by peers" ON public.conversation_members;
CREATE POLICY "Conversation members readable by peers"
  ON public.conversation_members FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.conversation_members me
      WHERE me.conversation_id = conversation_members.conversation_id
        AND me.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Members can update own membership row" ON public.conversation_members;
CREATE POLICY "Members can update own membership row"
  ON public.conversation_members FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Messages readable by members" ON public.messages;
CREATE POLICY "Messages readable by members"
  ON public.messages FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.conversation_members cm
      WHERE cm.conversation_id = messages.conversation_id
        AND cm.user_id = auth.uid()
    )
  );

-- Inserts go through SECURITY DEFINER RPCs (safer + flood control)
REVOKE INSERT ON public.conversations FROM authenticated;
REVOKE INSERT ON public.conversation_members FROM authenticated;
REVOKE INSERT ON public.messages FROM authenticated;
REVOKE UPDATE ON public.conversations FROM authenticated;
REVOKE DELETE ON public.messages FROM authenticated;

-- ============================================================
-- Helper: is member
-- ============================================================

CREATE OR REPLACE FUNCTION public.is_conversation_member(p_conversation_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.conversation_members
    WHERE conversation_id = p_conversation_id AND user_id = auth.uid()
  );
$$;

REVOKE ALL ON FUNCTION public.is_conversation_member(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_conversation_member(UUID) TO authenticated;

-- ============================================================
-- RPC: open market chat (buyer ↔ seller for listing)
-- ============================================================

CREATE OR REPLACE FUNCTION public.open_market_chat(p_listing_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_seller UUID;
  v_title TEXT;
  v_conv UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT seller_id, title INTO v_seller, v_title
  FROM public.listings
  WHERE id = p_listing_id AND status = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'LISTING_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_seller = v_uid THEN
    RAISE EXCEPTION 'CANNOT_CHAT_SELF' USING ERRCODE = 'P0001';
  END IF;

  -- Existing market chat for this listing + buyer
  SELECT c.id INTO v_conv
  FROM public.conversations c
  JOIN public.conversation_members cm ON cm.conversation_id = c.id
  WHERE c.type = 'market'
    AND c.listing_id = p_listing_id
    AND cm.user_id = v_uid
  LIMIT 1;

  IF v_conv IS NOT NULL THEN
    RETURN v_conv;
  END IF;

  INSERT INTO public.conversations (type, title, listing_id)
  VALUES ('market', v_title, p_listing_id)
  RETURNING id INTO v_conv;

  INSERT INTO public.conversation_members (conversation_id, user_id, role, last_read_at)
  VALUES
    (v_conv, v_uid, 'member', NOW()),
    (v_conv, v_seller, 'member', NULL)
  ON CONFLICT DO NOTHING;

  RETURN v_conv;
END;
$$;

REVOKE ALL ON FUNCTION public.open_market_chat(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.open_market_chat(UUID) TO authenticated;

-- ============================================================
-- RPC: open user DM (no duplicates)
-- ============================================================

CREATE OR REPLACE FUNCTION public.open_user_chat(p_other_user_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_nick TEXT;
  v_conv UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF p_other_user_id = v_uid THEN
    RAISE EXCEPTION 'CANNOT_CHAT_SELF' USING ERRCODE = 'P0001';
  END IF;

  SELECT nickname INTO v_nick FROM public.profiles WHERE id = p_other_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  SELECT c.id INTO v_conv
  FROM public.conversations c
  WHERE c.type = 'user'
    AND EXISTS (
      SELECT 1 FROM public.conversation_members m1
      WHERE m1.conversation_id = c.id AND m1.user_id = v_uid
    )
    AND EXISTS (
      SELECT 1 FROM public.conversation_members m2
      WHERE m2.conversation_id = c.id AND m2.user_id = p_other_user_id
    )
    AND (
      SELECT COUNT(*) FROM public.conversation_members mx
      WHERE mx.conversation_id = c.id
    ) = 2
  LIMIT 1;

  IF v_conv IS NOT NULL THEN
    RETURN v_conv;
  END IF;

  INSERT INTO public.conversations (type, title)
  VALUES ('user', v_nick)
  RETURNING id INTO v_conv;

  INSERT INTO public.conversation_members (conversation_id, user_id, role, last_read_at)
  VALUES
    (v_conv, v_uid, 'member', NOW()),
    (v_conv, p_other_user_id, 'member', NULL);

  RETURN v_conv;
END;
$$;

REVOKE ALL ON FUNCTION public.open_user_chat(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.open_user_chat(UUID) TO authenticated;

-- ============================================================
-- RPC: open / sync clan chat
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
  WHERE type = 'clan' AND clan_id = p_clan_id
  LIMIT 1;

  IF v_conv IS NULL THEN
    INSERT INTO public.conversations (type, title, clan_id)
    VALUES ('clan', v_name, p_clan_id)
    RETURNING id INTO v_conv;
  END IF;

  -- Sync all clan members into conversation
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
-- RPC: send message + flood protection (max 8 / 20s)
-- ============================================================

CREATE OR REPLACE FUNCTION public.send_chat_message(
  p_conversation_id UUID,
  p_text TEXT
)
RETURNS public.messages
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_text TEXT := trim(p_text);
  v_recent INTEGER;
  v_row public.messages;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF v_text IS NULL OR char_length(v_text) = 0 THEN
    RAISE EXCEPTION 'EMPTY_MESSAGE' USING ERRCODE = 'P0001';
  END IF;

  IF char_length(v_text) > 4000 THEN
    RAISE EXCEPTION 'MESSAGE_TOO_LONG' USING ERRCODE = 'P0001';
  END IF;

  IF NOT public.is_conversation_member(p_conversation_id) THEN
    RAISE EXCEPTION 'NOT_MEMBER' USING ERRCODE = '42501';
  END IF;

  SELECT COUNT(*)::INTEGER INTO v_recent
  FROM public.messages
  WHERE sender_id = v_uid
    AND created_at > NOW() - INTERVAL '20 seconds';

  IF v_recent >= 8 THEN
    RAISE EXCEPTION 'FLOOD' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.messages (conversation_id, sender_id, text)
  VALUES (p_conversation_id, v_uid, v_text)
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

REVOKE ALL ON FUNCTION public.send_chat_message(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.send_chat_message(UUID, TEXT) TO authenticated;

-- ============================================================
-- RPC: mark read
-- ============================================================

CREATE OR REPLACE FUNCTION public.mark_conversation_read(p_conversation_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  UPDATE public.conversation_members
  SET last_read_at = NOW()
  WHERE conversation_id = p_conversation_id
    AND user_id = auth.uid();
END;
$$;

REVOKE ALL ON FUNCTION public.mark_conversation_read(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_conversation_read(UUID) TO authenticated;

-- Realtime
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
  EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.conversations;
  EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.conversation_members;
  EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL;
  END;
END $$;
