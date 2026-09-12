-- ============================================================
-- Fix admin panel: ambiguous id + RLS recursion on admin_users
-- ============================================================

-- 1) Harden helpers so they never re-enter RLS on admin_users
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_users WHERE admin_users.id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.current_admin_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
  SELECT role FROM public.admin_users WHERE admin_users.id = auth.uid() LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.admin_has_perm(p_perm TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_role TEXT;
BEGIN
  SELECT role INTO v_role
  FROM public.admin_users
  WHERE admin_users.id = auth.uid();

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

-- 2) Break infinite recursion: policies must not SELECT admin_users directly
DROP POLICY IF EXISTS "Admins can read admin_users" ON public.admin_users;
CREATE POLICY "Admins can read admin_users"
  ON public.admin_users
  FOR SELECT
  TO authenticated
  USING (public.is_admin());

DROP POLICY IF EXISTS "Admins can read audit logs" ON public.admin_audit_logs;
CREATE POLICY "Admins can read audit logs"
  ON public.admin_audit_logs
  FOR SELECT
  TO authenticated
  USING (public.is_admin());

-- 3) Fix ambiguous `id` in admin_list_conversations
--    RETURNS TABLE(id ...) makes unqualified `id` collide with OUT param.
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

  SELECT au.role INTO v_role
  FROM public.admin_users au
  WHERE au.id = auth.uid();

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
    (SELECT COUNT(*)::BIGINT
       FROM public.conversation_members cm
      WHERE cm.conversation_id = c.id),
    (SELECT COUNT(*)::BIGINT
       FROM public.messages m
      WHERE m.conversation_id = c.id
        AND m.deleted_at IS NULL),
    (
      SELECT COUNT(*)::BIGINT
      FROM public.messages m
      WHERE m.conversation_id = c.id
        AND m.deleted_at IS NULL
        AND m.created_at > COALESCE(
          (SELECT MIN(cm2.last_read_at)
             FROM public.conversation_members cm2
            WHERE cm2.conversation_id = c.id),
          '1970-01-01'::timestamptz
        )
    ),
    (
      SELECT CASE
               WHEN m.deleted_at IS NOT NULL THEN '[удалено]'
               ELSE left(m.text, 120)
             END
      FROM public.messages m
      WHERE m.conversation_id = c.id
      ORDER BY m.created_at DESC
      LIMIT 1
    ),
    (
      SELECT m.created_at
      FROM public.messages m
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
        SELECT 1
        FROM public.conversation_members cm
        JOIN public.profiles p ON p.id = cm.user_id
        WHERE cm.conversation_id = c.id
          AND lower(p.nickname) LIKE '%' || v_q || '%'
      )
    )
  ORDER BY COALESCE(
    (SELECT m.created_at
       FROM public.messages m
      WHERE m.conversation_id = c.id
      ORDER BY m.created_at DESC
      LIMIT 1),
    c.updated_at
  ) DESC
  LIMIT v_limit OFFSET v_offset;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_conversations(TEXT, TEXT, TEXT, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_conversations(TEXT, TEXT, TEXT, INTEGER, INTEGER) TO authenticated;

NOTIFY pgrst, 'reload schema';
