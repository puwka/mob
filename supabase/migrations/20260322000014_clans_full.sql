-- ============================================================
-- Full clan system (extends minimal messaging clans)
-- Idempotent. Safe to re-run after a deadlock / partial apply.
--
-- IMPORTANT (Supabase SQL Editor):
-- 1) Close the app / stop polling the DB
-- 2) Run this whole script once
-- If deadlock returns: run each "PHASE" block separately
-- ============================================================

SET lock_timeout = '15s';
SET statement_timeout = '120s';

-- ============================================================
-- PHASE 1: columns on clans (no FK yet — shorter exclusive lock)
-- ============================================================

ALTER TABLE public.clans
  ADD COLUMN IF NOT EXISTS tag TEXT,
  ADD COLUMN IF NOT EXISTS description TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS leader_id UUID,
  ADD COLUMN IF NOT EXISTS rating INTEGER NOT NULL DEFAULT 0;

UPDATE public.clans
SET tag = UPPER(LEFT(REGEXP_REPLACE(COALESCE(name, 'CLAN'), '[^a-zA-Zа-яА-ЯёЁ0-9]', '', 'g'), 4))
WHERE tag IS NULL OR btrim(tag) = '';

DO $$
BEGIN
  ALTER TABLE public.clans ALTER COLUMN tag SET NOT NULL;
EXCEPTION
  WHEN others THEN NULL;
END $$;

COMMIT;

-- ============================================================
-- PHASE 2: FK + unique indexes
-- ============================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'clans_leader_id_fkey'
  ) THEN
    ALTER TABLE public.clans
      ADD CONSTRAINT clans_leader_id_fkey
      FOREIGN KEY (leader_id) REFERENCES public.profiles (id) ON DELETE SET NULL
      NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  ALTER TABLE public.clans VALIDATE CONSTRAINT clans_leader_id_fkey;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS clans_name_unique_idx
  ON public.clans (LOWER(name));
CREATE UNIQUE INDEX IF NOT EXISTS clans_tag_unique_idx
  ON public.clans (UPPER(tag));

COMMIT;

-- ============================================================
-- PHASE 3: clan_members role + one-clan-per-user
-- ============================================================
-- Drop ANY role check first, then rewrite owner → leader, then add new check.

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT c.conname
    FROM pg_constraint c
    WHERE c.conrelid = 'public.clan_members'::regclass
      AND c.contype = 'c'
      AND pg_get_constraintdef(c.oid) ILIKE '%role%'
  LOOP
    EXECUTE format(
      'ALTER TABLE public.clan_members DROP CONSTRAINT IF EXISTS %I',
      r.conname
    );
  END LOOP;
END $$;

UPDATE public.clan_members SET role = 'leader' WHERE role = 'owner';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.clan_members'::regclass
      AND conname = 'clan_members_role_check'
  ) THEN
    ALTER TABLE public.clan_members
      ADD CONSTRAINT clan_members_role_check
      CHECK (role IN ('leader', 'officer', 'member'));
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS clan_members_user_unique_idx
  ON public.clan_members (user_id);

COMMIT;

-- ============================================================
-- PHASE 4: join requests
-- ============================================================

CREATE TABLE IF NOT EXISTS public.clan_join_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clan_id UUID NOT NULL REFERENCES public.clans (id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (clan_id, user_id)
);

CREATE INDEX IF NOT EXISTS clan_join_requests_clan_idx
  ON public.clan_join_requests (clan_id, status);
CREATE INDEX IF NOT EXISTS clan_join_requests_user_idx
  ON public.clan_join_requests (user_id, status);

ALTER TABLE public.clan_join_requests ENABLE ROW LEVEL SECURITY;

COMMIT;

-- ============================================================
-- PHASE 5: rating functions + triggers
-- ============================================================

CREATE OR REPLACE FUNCTION public.recompute_clan_rating(p_clan_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sum INTEGER;
BEGIN
  SELECT COALESCE(SUM(p.rating), 0)::INTEGER INTO v_sum
  FROM public.clan_members cm
  JOIN public.profiles p ON p.id = cm.user_id
  WHERE cm.clan_id = p_clan_id;

  UPDATE public.clans SET rating = v_sum WHERE id = p_clan_id;
  RETURN v_sum;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_clan_members_rating()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.recompute_clan_rating(NEW.clan_id);
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    PERFORM public.recompute_clan_rating(OLD.clan_id);
    RETURN OLD;
  ELSIF TG_OP = 'UPDATE' AND NEW.clan_id IS DISTINCT FROM OLD.clan_id THEN
    PERFORM public.recompute_clan_rating(OLD.clan_id);
    PERFORM public.recompute_clan_rating(NEW.clan_id);
    RETURN NEW;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS clan_members_rating_aiud ON public.clan_members;
CREATE TRIGGER clan_members_rating_aiud
  AFTER INSERT OR UPDATE OR DELETE ON public.clan_members
  FOR EACH ROW
  EXECUTE PROCEDURE public.trg_clan_members_rating();

CREATE OR REPLACE FUNCTION public.trg_profile_rating_clan()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_clan UUID;
BEGIN
  IF NEW.rating IS DISTINCT FROM OLD.rating THEN
    SELECT clan_id INTO v_clan
    FROM public.clan_members
    WHERE user_id = NEW.id
    LIMIT 1;
    IF v_clan IS NOT NULL THEN
      PERFORM public.recompute_clan_rating(v_clan);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_rating_clan_au ON public.profiles;
CREATE TRIGGER profiles_rating_clan_au
  AFTER UPDATE OF rating ON public.profiles
  FOR EACH ROW
  EXECUTE PROCEDURE public.trg_profile_rating_clan();

CREATE OR REPLACE VIEW public.clans_with_stats AS
SELECT
  c.*,
  (SELECT COUNT(*)::INTEGER FROM public.clan_members cm WHERE cm.clan_id = c.id) AS members_count,
  lp.nickname AS leader_nickname
FROM public.clans c
LEFT JOIN public.profiles lp ON lp.id = c.leader_id;

GRANT SELECT ON public.clans_with_stats TO authenticated;

COMMIT;

-- ============================================================
-- PHASE 6: clan ↔ chat member sync
-- ============================================================

CREATE OR REPLACE FUNCTION public.sync_clan_conversation_member()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_conv UUID;
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT id INTO v_conv
    FROM public.conversations
    WHERE type = 'clan' AND clan_id = NEW.clan_id
    LIMIT 1;

    IF v_conv IS NULL THEN
      INSERT INTO public.conversations (type, title, clan_id)
      SELECT 'clan', name, id FROM public.clans WHERE id = NEW.clan_id
      RETURNING id INTO v_conv;
    END IF;

    INSERT INTO public.conversation_members (conversation_id, user_id, role)
    VALUES (v_conv, NEW.user_id, 'member')
    ON CONFLICT DO NOTHING;

    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    SELECT id INTO v_conv
    FROM public.conversations
    WHERE type = 'clan' AND clan_id = OLD.clan_id
    LIMIT 1;

    IF v_conv IS NOT NULL THEN
      DELETE FROM public.conversation_members
      WHERE conversation_id = v_conv AND user_id = OLD.user_id;
    END IF;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS clan_members_sync_chat ON public.clan_members;
CREATE TRIGGER clan_members_sync_chat
  AFTER INSERT OR DELETE ON public.clan_members
  FOR EACH ROW
  EXECUTE PROCEDURE public.sync_clan_conversation_member();

COMMIT;

-- ============================================================
-- PHASE 7: RLS
-- ============================================================

DROP POLICY IF EXISTS "Clans readable by members" ON public.clans;
DROP POLICY IF EXISTS "Clans readable by authenticated" ON public.clans;
CREATE POLICY "Clans readable by authenticated"
  ON public.clans
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Clan members readable by clan mates" ON public.clan_members;
DROP POLICY IF EXISTS "Clan members readable by authenticated" ON public.clan_members;
CREATE POLICY "Clan members readable by authenticated"
  ON public.clan_members
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Join requests readable" ON public.clan_join_requests;
CREATE POLICY "Join requests readable"
  ON public.clan_join_requests
  FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_clan_member(clan_id)
  );

REVOKE INSERT, UPDATE, DELETE ON public.clans FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.clan_members FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.clan_join_requests FROM authenticated;
GRANT SELECT ON public.clans TO authenticated;
GRANT SELECT ON public.clan_members TO authenticated;
GRANT SELECT ON public.clan_join_requests TO authenticated;

COMMIT;

-- ============================================================
-- PHASE 8: RPCs
-- ============================================================

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

  SELECT id INTO v_conv FROM public.conversations
  WHERE type = 'clan' AND clan_id = v_clan;
  IF v_conv IS NULL THEN
    INSERT INTO public.conversations (type, title, clan_id)
    VALUES ('clan', v_name, v_clan);
  END IF;

  PERFORM public.recompute_clan_rating(v_clan);
  RETURN v_clan;
END;
$$;

REVOKE ALL ON FUNCTION public.create_clan(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_clan(TEXT, TEXT, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_clan_avatar(
  p_clan_id UUID,
  p_avatar_url TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_role TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT role INTO v_role
  FROM public.clan_members
  WHERE clan_id = p_clan_id AND user_id = v_uid;

  IF v_role IS NULL OR v_role <> 'leader' THEN
    RAISE EXCEPTION 'NOT_ALLOWED' USING ERRCODE = '42501';
  END IF;

  UPDATE public.clans SET avatar_url = p_avatar_url WHERE id = p_clan_id;
END;
$$;

REVOKE ALL ON FUNCTION public.set_clan_avatar(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_clan_avatar(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.request_clan_join(p_clan_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_id UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.clans WHERE id = p_clan_id) THEN
    RAISE EXCEPTION 'CLAN_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF EXISTS (SELECT 1 FROM public.clan_members WHERE user_id = v_uid) THEN
    RAISE EXCEPTION 'ALREADY_IN_CLAN' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.clan_join_requests (clan_id, user_id, status)
  VALUES (p_clan_id, v_uid, 'pending')
  ON CONFLICT (clan_id, user_id) DO UPDATE
    SET status = 'pending',
        created_at = NOW()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.request_clan_join(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_clan_join(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.decide_clan_join(
  p_request_id UUID,
  p_approve BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_clan UUID;
  v_user UUID;
  v_status TEXT;
  v_role TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT clan_id, user_id, status INTO v_clan, v_user, v_status
  FROM public.clan_join_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'REQUEST_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'REQUEST_NOT_PENDING' USING ERRCODE = 'P0001';
  END IF;

  SELECT role INTO v_role
  FROM public.clan_members
  WHERE clan_id = v_clan AND user_id = v_uid;

  IF v_role IS NULL OR v_role NOT IN ('leader', 'officer') THEN
    RAISE EXCEPTION 'NOT_ALLOWED' USING ERRCODE = '42501';
  END IF;

  IF p_approve THEN
    IF EXISTS (SELECT 1 FROM public.clan_members WHERE user_id = v_user) THEN
      UPDATE public.clan_join_requests SET status = 'rejected' WHERE id = p_request_id;
      RAISE EXCEPTION 'ALREADY_IN_CLAN' USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO public.clan_members (clan_id, user_id, role)
    VALUES (v_clan, v_user, 'member')
    ON CONFLICT DO NOTHING;

    UPDATE public.clan_join_requests SET status = 'approved' WHERE id = p_request_id;
  ELSE
    UPDATE public.clan_join_requests SET status = 'rejected' WHERE id = p_request_id;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.decide_clan_join(UUID, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.decide_clan_join(UUID, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.leave_clan()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_clan UUID;
  v_role TEXT;
  v_new_leader UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT clan_id, role INTO v_clan, v_role
  FROM public.clan_members
  WHERE user_id = v_uid;

  IF v_clan IS NULL THEN
    RAISE EXCEPTION 'NOT_IN_CLAN' USING ERRCODE = 'P0001';
  END IF;

  IF v_role = 'leader' THEN
    SELECT user_id INTO v_new_leader
    FROM public.clan_members
    WHERE clan_id = v_clan AND user_id <> v_uid
    ORDER BY CASE role WHEN 'officer' THEN 0 ELSE 1 END, joined_at
    LIMIT 1;

    IF v_new_leader IS NULL THEN
      DELETE FROM public.clans WHERE id = v_clan;
      RETURN;
    END IF;

    UPDATE public.clan_members SET role = 'leader' WHERE clan_id = v_clan AND user_id = v_new_leader;
    UPDATE public.clans SET leader_id = v_new_leader WHERE id = v_clan;
  END IF;

  DELETE FROM public.clan_members WHERE clan_id = v_clan AND user_id = v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.leave_clan() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.leave_clan() TO authenticated;

CREATE OR REPLACE FUNCTION public.kick_clan_member(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_clan UUID;
  v_my_role TEXT;
  v_target_role TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF p_user_id = v_uid THEN
    RAISE EXCEPTION 'USE_LEAVE' USING ERRCODE = 'P0001';
  END IF;

  SELECT clan_id, role INTO v_clan, v_my_role
  FROM public.clan_members WHERE user_id = v_uid;

  IF v_clan IS NULL OR v_my_role NOT IN ('leader', 'officer') THEN
    RAISE EXCEPTION 'NOT_ALLOWED' USING ERRCODE = '42501';
  END IF;

  SELECT role INTO v_target_role
  FROM public.clan_members
  WHERE clan_id = v_clan AND user_id = p_user_id;

  IF v_target_role IS NULL THEN
    RAISE EXCEPTION 'NOT_MEMBER' USING ERRCODE = 'P0002';
  END IF;

  IF v_target_role = 'leader' THEN
    RAISE EXCEPTION 'NOT_ALLOWED' USING ERRCODE = '42501';
  END IF;

  IF v_my_role = 'officer' AND v_target_role = 'officer' THEN
    RAISE EXCEPTION 'NOT_ALLOWED' USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.clan_members WHERE clan_id = v_clan AND user_id = p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.kick_clan_member(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.kick_clan_member(UUID) TO authenticated;

COMMIT;

-- ============================================================
-- PHASE 9: backfill
-- ============================================================

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT id FROM public.clans LOOP
    PERFORM public.recompute_clan_rating(r.id);
  END LOOP;
END $$;

UPDATE public.clan_members
SET role = 'leader'
WHERE role = 'owner';

UPDATE public.clans c
SET leader_id = cm.user_id,
    tag = COALESCE(NULLIF(c.tag, ''), 'STL')
FROM public.clan_members cm
WHERE cm.clan_id = c.id AND cm.role = 'leader' AND c.leader_id IS NULL;

COMMIT;
