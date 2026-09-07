-- ============================================================
-- Fix RLS infinite recursion on conversation_members / clan_members
-- ============================================================

-- Membership checks must bypass RLS (SECURITY DEFINER)
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
  );
$$;

CREATE OR REPLACE FUNCTION public.is_clan_member(p_clan_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.clan_members
    WHERE clan_id = p_clan_id
      AND user_id = auth.uid()
  );
$$;

REVOKE ALL ON FUNCTION public.is_conversation_member(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_conversation_member(UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.is_clan_member(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_clan_member(UUID) TO authenticated;

-- conversation_members: allow own row OR peer rows in same conversation
DROP POLICY IF EXISTS "Conversation members readable by peers"
  ON public.conversation_members;
CREATE POLICY "Conversation members readable by peers"
  ON public.conversation_members
  FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_conversation_member(conversation_id)
  );

-- conversations
DROP POLICY IF EXISTS "Conversations readable by members"
  ON public.conversations;
CREATE POLICY "Conversations readable by members"
  ON public.conversations
  FOR SELECT
  TO authenticated
  USING (public.is_conversation_member(id));

-- messages
DROP POLICY IF EXISTS "Messages readable by members"
  ON public.messages;
CREATE POLICY "Messages readable by members"
  ON public.messages
  FOR SELECT
  TO authenticated
  USING (public.is_conversation_member(conversation_id));

-- clans / clan_members
DROP POLICY IF EXISTS "Clans readable by members" ON public.clans;
CREATE POLICY "Clans readable by members"
  ON public.clans
  FOR SELECT
  TO authenticated
  USING (public.is_clan_member(id));

DROP POLICY IF EXISTS "Clan members readable by clan mates"
  ON public.clan_members;
CREATE POLICY "Clan members readable by clan mates"
  ON public.clan_members
  FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_clan_member(clan_id)
  );

-- Ensure authenticated can SELECT (RLS still applies)
GRANT SELECT ON public.clans TO authenticated;
GRANT SELECT ON public.clan_members TO authenticated;
GRANT SELECT ON public.conversations TO authenticated;
GRANT SELECT ON public.conversation_members TO authenticated;
GRANT SELECT ON public.messages TO authenticated;
GRANT UPDATE (last_read_at, role) ON public.conversation_members TO authenticated;
