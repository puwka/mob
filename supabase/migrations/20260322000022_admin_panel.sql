-- ============================================================
-- Web admin panel: admin_users, audit logs, profile status,
-- secure admin RPCs (separate from organizer role)
-- ============================================================

-- 1) Profile status (block / unblock)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS status TEXT;

UPDATE public.profiles
SET status = 'active'
WHERE status IS NULL OR status NOT IN ('active', 'blocked');

ALTER TABLE public.profiles
  ALTER COLUMN status SET DEFAULT 'active',
  ALTER COLUMN status SET NOT NULL;

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_status_check;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_status_check
  CHECK (status IN ('active', 'blocked'));

CREATE INDEX IF NOT EXISTS profiles_status_idx ON public.profiles (status);

-- 2) Admin users (linked to auth.users; NOT profiles.role)
CREATE TABLE IF NOT EXISTS public.admin_users (
  id UUID PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  phone TEXT NOT NULL UNIQUE,
  role TEXT NOT NULL DEFAULT 'admin'
    CHECK (role IN ('super_admin', 'admin', 'moderator')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS admin_users_role_idx ON public.admin_users (role);

ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can read admin_users" ON public.admin_users;
CREATE POLICY "Admins can read admin_users"
  ON public.admin_users
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users au WHERE au.id = auth.uid()
    )
  );

-- No INSERT/UPDATE/DELETE for authenticated — only via SQL / service_role / RPC

-- 3) Audit logs
CREATE TABLE IF NOT EXISTS public.admin_audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id UUID NOT NULL REFERENCES public.admin_users (id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT,
  old_data JSONB,
  new_data JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS admin_audit_logs_created_idx
  ON public.admin_audit_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS admin_audit_logs_admin_idx
  ON public.admin_audit_logs (admin_id);
CREATE INDEX IF NOT EXISTS admin_audit_logs_entity_idx
  ON public.admin_audit_logs (entity_type, entity_id);

ALTER TABLE public.admin_audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can read audit logs" ON public.admin_audit_logs;
CREATE POLICY "Admins can read audit logs"
  ON public.admin_audit_logs
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users au WHERE au.id = auth.uid()
    )
  );

-- 4) Helpers
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_users WHERE id = auth.uid()
  );
$$;

REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;

CREATE OR REPLACE FUNCTION public.current_admin_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role FROM public.admin_users WHERE id = auth.uid() LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.current_admin_role() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.current_admin_role() TO authenticated;

CREATE OR REPLACE FUNCTION public.require_admin(p_min_role TEXT DEFAULT 'moderator')
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_role TEXT;
  v_rank INTEGER;
  v_need INTEGER;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT role INTO v_role FROM public.admin_users WHERE id = v_uid;
  IF v_role IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  v_rank := CASE v_role
    WHEN 'super_admin' THEN 3
    WHEN 'admin' THEN 2
    WHEN 'moderator' THEN 1
    ELSE 0
  END;
  v_need := CASE p_min_role
    WHEN 'super_admin' THEN 3
    WHEN 'admin' THEN 2
    WHEN 'moderator' THEN 1
    ELSE 3
  END;

  IF v_rank < v_need THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  RETURN v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.require_admin(TEXT) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.write_admin_audit(
  p_admin_id UUID,
  p_action TEXT,
  p_entity_type TEXT,
  p_entity_id TEXT,
  p_old JSONB,
  p_new JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.admin_audit_logs (
    admin_id, action, entity_type, entity_id, old_data, new_data
  ) VALUES (
    p_admin_id, p_action, p_entity_type, p_entity_id, p_old, p_new
  );
END;
$$;

REVOKE ALL ON FUNCTION public.write_admin_audit(UUID, TEXT, TEXT, TEXT, JSONB, JSONB) FROM PUBLIC;

-- 5) Allow admins to bypass client locks on profiles
CREATE OR REPLACE FUNCTION public.protect_profile_role_and_qr()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.role := 'user';
    IF NEW.public_qr_id IS NULL THEN
      NEW.public_qr_id := gen_random_uuid();
    END IF;
    IF NEW.status IS NULL THEN
      NEW.status := 'active';
    END IF;
    RETURN NEW;
  END IF;

  -- Clients cannot change app role / QR / status — admins can via RPCs (same JWT)
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    NEW.role := OLD.role;
    NEW.public_qr_id := OLD.public_qr_id;
    NEW.status := OLD.status;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.protect_profile_stats()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Own profile: lock combat stats / phone (admins updating others OK;
  -- admin editing own linked profile still locked unless via RPC)
  IF TG_OP = 'UPDATE'
     AND auth.uid() = NEW.id
     AND NOT public.is_admin() THEN
    NEW.games_played := OLD.games_played;
    NEW.wins := OLD.wins;
    NEW.rating := OLD.rating;
    NEW.polygons_visited := OLD.polygons_visited;
    NEW.phone := OLD.phone;
    NEW.created_at := OLD.created_at;
    NEW.role := OLD.role;
    NEW.public_qr_id := OLD.public_qr_id;
    NEW.status := OLD.status;
  END IF;
  RETURN NEW;
END;
$$;

-- Column grants: status still not client-updatable
REVOKE UPDATE ON public.profiles FROM authenticated;
GRANT UPDATE (
  nickname,
  city,
  avatar_url,
  bio,
  game_role,
  team_name
) ON public.profiles TO authenticated;

-- Admins may read everything they need via policies
DROP POLICY IF EXISTS "Admins full read profiles" ON public.profiles;
-- Already readable by authenticated

-- 6) Replace admin_set_app_role: allow admin_users OR service_role
CREATE OR REPLACE FUNCTION public.admin_set_app_role(
  p_user_id UUID,
  p_role TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_old TEXT;
BEGIN
  IF p_role IS NULL OR p_role NOT IN ('user', 'organizer') THEN
    RAISE EXCEPTION 'INVALID_ROLE' USING ERRCODE = 'P0001';
  END IF;

  IF auth.role() = 'authenticated' THEN
    v_admin := public.require_admin('admin');
  ELSIF auth.role() IN ('service_role', 'postgres') OR current_user IN ('postgres', 'supabase_admin') THEN
    v_admin := NULL;
  ELSE
    -- SQL editor / elevated
    v_admin := NULL;
  END IF;

  SELECT role INTO v_old FROM public.profiles WHERE id = p_user_id;
  IF v_old IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.profiles
  SET role = p_role
  WHERE id = p_user_id;

  IF p_role = 'organizer' THEN
    PERFORM public.ensure_organizer_wallet(p_user_id);
  END IF;

  IF v_admin IS NOT NULL THEN
    PERFORM public.write_admin_audit(
      v_admin,
      'set_app_role',
      'profile',
      p_user_id::TEXT,
      jsonb_build_object('role', v_old),
      jsonb_build_object('role', p_role)
    );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_app_role(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_app_role(UUID, TEXT) TO authenticated;

-- 7) Admin update profile (critical fields)
CREATE OR REPLACE FUNCTION public.admin_update_profile(
  p_user_id UUID,
  p_nickname TEXT DEFAULT NULL,
  p_city TEXT DEFAULT NULL,
  p_bio TEXT DEFAULT NULL,
  p_avatar_url TEXT DEFAULT NULL,
  p_clear_bio BOOLEAN DEFAULT FALSE,
  p_clear_avatar BOOLEAN DEFAULT FALSE,
  p_role TEXT DEFAULT NULL,
  p_rating INTEGER DEFAULT NULL,
  p_games_played INTEGER DEFAULT NULL,
  p_wins INTEGER DEFAULT NULL,
  p_polygons_visited INTEGER DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_game_role TEXT DEFAULT NULL,
  p_team_name TEXT DEFAULT NULL
)
RETURNS public.profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_old public.profiles;
  v_new public.profiles;
BEGIN
  v_admin := public.require_admin('moderator');

  SELECT * INTO v_old FROM public.profiles WHERE id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  -- Role change requires admin+
  IF p_role IS NOT NULL AND p_role IS DISTINCT FROM v_old.role THEN
    PERFORM public.require_admin('admin');
    IF p_role NOT IN ('user', 'organizer') THEN
      RAISE EXCEPTION 'INVALID_ROLE' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  IF p_status IS NOT NULL AND p_status NOT IN ('active', 'blocked') THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.profiles SET
    nickname = COALESCE(NULLIF(trim(p_nickname), ''), nickname),
    city = COALESCE(NULLIF(trim(p_city), ''), city),
    bio = CASE
      WHEN p_clear_bio THEN NULL
      WHEN p_bio IS NOT NULL THEN p_bio
      ELSE bio
    END,
    avatar_url = CASE
      WHEN p_clear_avatar THEN NULL
      WHEN p_avatar_url IS NOT NULL THEN p_avatar_url
      ELSE avatar_url
    END,
    role = COALESCE(p_role, role),
    rating = COALESCE(p_rating, rating),
    games_played = COALESCE(p_games_played, games_played),
    wins = COALESCE(p_wins, wins),
    polygons_visited = COALESCE(p_polygons_visited, polygons_visited),
    status = COALESCE(p_status, status),
    game_role = COALESCE(p_game_role, game_role),
    team_name = COALESCE(p_team_name, team_name)
  WHERE id = p_user_id
  RETURNING * INTO v_new;

  IF p_role = 'organizer' AND v_old.role IS DISTINCT FROM 'organizer' THEN
    PERFORM public.ensure_organizer_wallet(p_user_id);
  END IF;

  PERFORM public.write_admin_audit(
    v_admin,
    'update_profile',
    'profile',
    p_user_id::TEXT,
    to_jsonb(v_old),
    to_jsonb(v_new)
  );

  RETURN v_new;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_profile(
  UUID, TEXT, TEXT, TEXT, TEXT, BOOLEAN, BOOLEAN, TEXT,
  INTEGER, INTEGER, INTEGER, INTEGER, TEXT, TEXT, TEXT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_profile(
  UUID, TEXT, TEXT, TEXT, TEXT, BOOLEAN, BOOLEAN, TEXT,
  INTEGER, INTEGER, INTEGER, INTEGER, TEXT, TEXT, TEXT
) TO authenticated;

-- 8) Block / unblock shortcuts
CREATE OR REPLACE FUNCTION public.admin_set_user_status(
  p_user_id UUID,
  p_status TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.admin_update_profile(
    p_user_id := p_user_id,
    p_status := p_status
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_user_status(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_user_status(UUID, TEXT) TO authenticated;

-- 9) Manual wallet adjustment
CREATE OR REPLACE FUNCTION public.admin_adjust_organizer_balance(
  p_organizer_id UUID,
  p_amount NUMERIC,
  p_reason TEXT DEFAULT 'manual_adjustment'
)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_balance NUMERIC;
  v_old NUMERIC;
BEGIN
  v_admin := public.require_admin('admin');

  IF p_amount = 0 THEN
    RAISE EXCEPTION 'INVALID_AMOUNT' USING ERRCODE = 'P0001';
  END IF;

  PERFORM public.ensure_organizer_wallet(p_organizer_id);

  SELECT balance INTO v_old
  FROM public.organizer_wallets
  WHERE organizer_id = p_organizer_id
  FOR UPDATE;

  v_balance := v_old + p_amount;
  IF v_balance < 0 THEN
    RAISE EXCEPTION 'INSUFFICIENT_BALANCE' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.organizer_wallets
  SET balance = v_balance, updated_at = NOW()
  WHERE organizer_id = p_organizer_id;

  INSERT INTO public.organizer_transactions (
    organizer_id, amount, type, description
  ) VALUES (
    p_organizer_id,
    p_amount,
    'manual_adjustment',
    COALESCE(p_reason, 'manual_adjustment') || ' [admin:' || v_admin::TEXT || ']'
  );

  PERFORM public.write_admin_audit(
    v_admin,
    'adjust_balance',
    'organizer_wallet',
    p_organizer_id::TEXT,
    jsonb_build_object('balance', v_old),
    jsonb_build_object('balance', v_balance, 'amount', p_amount, 'reason', p_reason)
  );

  RETURN v_balance;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_adjust_organizer_balance(UUID, NUMERIC, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_adjust_organizer_balance(UUID, NUMERIC, TEXT) TO authenticated;

-- 10) Dashboard stats
CREATE OR REPLACE FUNCTION public.admin_dashboard_stats()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_since TIMESTAMPTZ := NOW() - INTERVAL '7 days';
BEGIN
  v_admin := public.require_admin('moderator');

  RETURN jsonb_build_object(
    'users_total', (SELECT COUNT(*) FROM public.profiles),
    'users_new_7d', (SELECT COUNT(*) FROM public.profiles WHERE created_at >= v_since),
    'organizers', (SELECT COUNT(*) FROM public.profiles WHERE role = 'organizer'),
    'events_total', (SELECT COUNT(*) FROM public.events),
    'events_active', (SELECT COUNT(*) FROM public.events WHERE status = 'active'),
    'clans_total', (SELECT COUNT(*) FROM public.clans),
    'listings_active', (SELECT COUNT(*) FROM public.listings WHERE status = 'active'),
    'messages_total', (SELECT COUNT(*) FROM public.messages WHERE deleted_at IS NULL),
    'attendance_confirmed', (
      SELECT COUNT(*) FROM public.event_participants
      WHERE attendance_status = 'confirmed'
    ),
    'credits_awarded_total', (
      SELECT COALESCE(SUM(amount), 0) FROM public.organizer_transactions
      WHERE amount > 0
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_dashboard_stats() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_stats() TO authenticated;

-- 11) Recent activity feed
CREATE OR REPLACE FUNCTION public.admin_recent_activity(p_limit INTEGER DEFAULT 20)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);
BEGIN
  PERFORM public.require_admin('moderator');

  RETURN (
    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'kind', x.kind,
          'entity_id', x.entity_id,
          'title', x.title,
          'at', x.at
        )
        ORDER BY x.at DESC NULLS LAST
      ),
      '[]'::jsonb
    )
    FROM (
      SELECT *
      FROM (
        (
          SELECT
            'new_user'::TEXT AS kind,
            p.id::TEXT AS entity_id,
            p.nickname AS title,
            p.created_at AS at
          FROM public.profiles p
          ORDER BY p.created_at DESC
          LIMIT v_limit
        )
        UNION ALL
        (
          SELECT
            'new_event'::TEXT,
            e.id::TEXT,
            e.title,
            e.created_at
          FROM public.events e
          ORDER BY e.created_at DESC
          LIMIT v_limit
        )
        UNION ALL
        (
          SELECT
            'clan_join_request'::TEXT,
            r.id::TEXT,
            COALESCE(c.name, 'Clan') || ' ← ' || COALESCE(pr.nickname, 'user'),
            r.created_at
          FROM public.clan_join_requests r
          LEFT JOIN public.clans c ON c.id = r.clan_id
          LEFT JOIN public.profiles pr ON pr.id = r.user_id
          WHERE r.status = 'pending'
          ORDER BY r.created_at DESC
          LIMIT v_limit
        )
        UNION ALL
        (
          SELECT
            'new_listing'::TEXT,
            l.id::TEXT,
            l.title,
            l.created_at
          FROM public.listings l
          ORDER BY l.created_at DESC
          LIMIT v_limit
        )
        UNION ALL
        (
          SELECT
            'achievement_unlock'::TEXT,
            ua.user_id::TEXT || ':' || ua.achievement_id::TEXT,
            COALESCE(a.title, 'Achievement') || ' — ' || COALESCE(pr.nickname, ''),
            ua.unlocked_at
          FROM public.user_achievements ua
          LEFT JOIN public.achievements a ON a.id = ua.achievement_id
          LEFT JOIN public.profiles pr ON pr.id = ua.user_id
          WHERE ua.unlocked = true AND ua.unlocked_at IS NOT NULL
          ORDER BY ua.unlocked_at DESC
          LIMIT v_limit
        )
      ) u
      ORDER BY u.at DESC NULLS LAST
      LIMIT v_limit
    ) x
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_recent_activity(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_recent_activity(INTEGER) TO authenticated;

-- 12) List users for admin (with clan)
CREATE OR REPLACE FUNCTION public.admin_list_users(
  p_search TEXT DEFAULT NULL,
  p_role TEXT DEFAULT NULL,
  p_city TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_clan_id UUID DEFAULT NULL,
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  nickname TEXT,
  phone TEXT,
  city TEXT,
  avatar_url TEXT,
  role TEXT,
  rating INTEGER,
  status TEXT,
  created_at TIMESTAMPTZ,
  clan_id UUID,
  clan_name TEXT,
  games_played INTEGER,
  wins INTEGER,
  polygons_visited INTEGER,
  bio TEXT,
  game_role TEXT,
  team_name TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
  v_offset INTEGER := GREATEST(COALESCE(p_offset, 0), 0);
  v_q TEXT := NULLIF(lower(trim(COALESCE(p_search, ''))), '');
BEGIN
  v_admin := public.require_admin('moderator');

  RETURN QUERY
  SELECT
    p.id,
    p.nickname,
    p.phone,
    p.city,
    p.avatar_url,
    p.role,
    p.rating,
    p.status,
    p.created_at,
    c.id,
    c.name,
    p.games_played,
    p.wins,
    p.polygons_visited,
    p.bio,
    p.game_role,
    p.team_name
  FROM public.profiles p
  LEFT JOIN public.clan_members cm ON cm.user_id = p.id
  LEFT JOIN public.clans c ON c.id = cm.clan_id
  WHERE (p_role IS NULL OR p.role = p_role)
    AND (p_city IS NULL OR p.city = p_city)
    AND (p_status IS NULL OR p.status = p_status)
    AND (p_clan_id IS NULL OR c.id = p_clan_id)
    AND (
      v_q IS NULL
      OR lower(p.nickname) LIKE '%' || v_q || '%'
      OR p.phone LIKE '%' || v_q || '%'
    )
  ORDER BY p.created_at DESC
  LIMIT v_limit OFFSET v_offset;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_users(TEXT, TEXT, TEXT, TEXT, UUID, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_users(TEXT, TEXT, TEXT, TEXT, UUID, INTEGER, INTEGER) TO authenticated;

-- 13) Organizer list with stats
CREATE OR REPLACE FUNCTION public.admin_list_organizers(
  p_search TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  nickname TEXT,
  avatar_url TEXT,
  city TEXT,
  status TEXT,
  created_at TIMESTAMPTZ,
  events_count BIGINT,
  participants_count BIGINT,
  balance NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
  v_offset INTEGER := GREATEST(COALESCE(p_offset, 0), 0);
  v_q TEXT := NULLIF(lower(trim(COALESCE(p_search, ''))), '');
BEGIN
  v_admin := public.require_admin('moderator');

  RETURN QUERY
  SELECT
    p.id,
    p.nickname,
    p.avatar_url,
    p.city,
    p.status,
    p.created_at,
    (SELECT COUNT(*) FROM public.events e WHERE e.organizer_id = p.id),
    (
      SELECT COUNT(*)
      FROM public.event_participants ep
      JOIN public.events e ON e.id = ep.event_id
      WHERE e.organizer_id = p.id
        AND ep.registration_status = 'registered'
    ),
    COALESCE(w.balance, 0)
  FROM public.profiles p
  LEFT JOIN public.organizer_wallets w ON w.organizer_id = p.id
  WHERE p.role = 'organizer'
    AND (p_status IS NULL OR p.status = p_status)
    AND (
      v_q IS NULL
      OR lower(p.nickname) LIKE '%' || v_q || '%'
      OR p.phone LIKE '%' || v_q || '%'
    )
  ORDER BY p.created_at DESC
  LIMIT v_limit OFFSET v_offset;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_organizers(TEXT, TEXT, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_organizers(TEXT, TEXT, INTEGER, INTEGER) TO authenticated;

-- 14) Who am I (admin session check)
CREATE OR REPLACE FUNCTION public.admin_me()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.admin_users;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_row FROM public.admin_users WHERE id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object(
    'id', v_row.id,
    'phone', v_row.phone,
    'role', v_row.role,
    'created_at', v_row.created_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_me() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_me() TO authenticated;

COMMENT ON TABLE public.admin_users IS 'Web admin accounts (separate from profiles.role organizer)';
COMMENT ON TABLE public.admin_audit_logs IS 'Immutable audit trail for admin actions';

-- 15) Admin read access to economy / related tables
DROP POLICY IF EXISTS "Admins read wallets" ON public.organizer_wallets;
CREATE POLICY "Admins read wallets"
  ON public.organizer_wallets
  FOR SELECT
  TO authenticated
  USING (public.is_admin());

DROP POLICY IF EXISTS "Admins read transactions" ON public.organizer_transactions;
CREATE POLICY "Admins read transactions"
  ON public.organizer_transactions
  FOR SELECT
  TO authenticated
  USING (public.is_admin());

DROP POLICY IF EXISTS "Admins read app settings" ON public.app_settings;
CREATE POLICY "Admins read app settings"
  ON public.app_settings
  FOR SELECT
  TO authenticated
  USING (public.is_admin());

DROP POLICY IF EXISTS "Admins read user achievements" ON public.user_achievements;
CREATE POLICY "Admins read user achievements"
  ON public.user_achievements
  FOR SELECT
  TO authenticated
  USING (public.is_admin());

DROP POLICY IF EXISTS "Admins read event participants" ON public.event_participants;
CREATE POLICY "Admins read event participants"
  ON public.event_participants
  FOR SELECT
  TO authenticated
  USING (public.is_admin());

-- Bootstrap note (create Auth user with email = 79001234567@phone.local):
-- INSERT INTO public.admin_users (id, phone, role)
-- VALUES ('<auth.users.id>', '+79001234567', 'super_admin');
