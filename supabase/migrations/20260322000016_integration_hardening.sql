-- ============================================================
-- Integration hardening: unique DMs, folder unread, security
-- ============================================================

-- Prevent duplicate user↔ under concurrent open_user_chat
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
  v_a UUID;
  v_b UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF p_other_user_id = v_uid THEN
    RAISE EXCEPTION 'CANNOT_CHAT_SELF' USING ERRCODE = 'P0001';
  END IF;

  -- Serialize pair creation (order-independent lock)
  IF v_uid < p_other_user_id THEN
    v_a := v_uid;
    v_b := p_other_user_id;
  ELSE
    v_a := p_other_user_id;
    v_b := v_uid;
  END IF;
  PERFORM pg_advisory_xact_lock(
    hashtext(v_a::text || ':' || v_b::text)
  );

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

-- Unread totals per dialog folder for current user
CREATE OR REPLACE FUNCTION public.conversation_unread_by_type()
RETURNS TABLE (
  type TEXT,
  unread_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH my_memberships AS (
    SELECT cm.conversation_id, cm.last_read_at, c.type AS ctype
    FROM public.conversation_members cm
    JOIN public.conversations c ON c.id = cm.conversation_id
    WHERE cm.user_id = auth.uid()
  ),
  unread AS (
    SELECT
      m.ctype AS type,
      COUNT(msg.id) AS unread_count
    FROM my_memberships m
    JOIN public.messages msg
      ON msg.conversation_id = m.conversation_id
     AND msg.sender_id <> auth.uid()
     AND msg.deleted_at IS NULL
     AND (
       m.last_read_at IS NULL
       OR msg.created_at > m.last_read_at
     )
    GROUP BY m.ctype
  )
  SELECT t.type, COALESCE(u.unread_count, 0)::BIGINT
  FROM (VALUES ('market'), ('clan'), ('user')) AS t(type)
  LEFT JOIN unread u ON u.type = t.type;
$$;

REVOKE ALL ON FUNCTION public.conversation_unread_by_type() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.conversation_unread_by_type() TO authenticated;

-- Harden: no direct client writes to rating fields via grants
REVOKE UPDATE ON public.profiles FROM authenticated;
GRANT UPDATE (
  nickname,
  city,
  avatar_url,
  bio,
  role,
  team_name
) ON public.profiles TO authenticated;

REVOKE INSERT, UPDATE, DELETE ON public.clans FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.clan_members FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.clan_join_requests FROM authenticated;
GRANT SELECT ON public.clans TO authenticated;
GRANT SELECT ON public.clan_members TO authenticated;
GRANT SELECT ON public.clan_join_requests TO authenticated;
