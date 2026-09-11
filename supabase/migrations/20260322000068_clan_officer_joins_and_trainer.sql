-- Deputy (officer): view/decide join requests + assign trainer/member

CREATE OR REPLACE FUNCTION public.can_manage_clan_joins(p_clan_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.clan_members cm
    WHERE cm.clan_id = p_clan_id
      AND cm.user_id = auth.uid()
      AND cm.role IN ('leader', 'officer')
  );
$$;

REVOKE ALL ON FUNCTION public.can_manage_clan_joins(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_manage_clan_joins(UUID) TO authenticated;

DROP POLICY IF EXISTS "Join requests readable" ON public.clan_join_requests;
CREATE POLICY "Join requests readable"
  ON public.clan_join_requests
  FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid()
    OR public.can_manage_clan_joins(clan_id)
  );

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

COMMENT ON FUNCTION public.decide_clan_join(UUID, BOOLEAN) IS
  'Approve/reject clan join — leader or officer (deputy)';

-- Leader: officer/trainer/member. Officer: trainer/member only (not other deputies).
CREATE OR REPLACE FUNCTION public.set_clan_member_role(
  p_user_id UUID,
  p_role TEXT
)
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
  v_role TEXT := lower(btrim(COALESCE(p_role, '')));
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF p_user_id = v_uid THEN
    RAISE EXCEPTION 'NOT_ALLOWED' USING ERRCODE = '42501';
  END IF;

  SELECT clan_id, role INTO v_clan, v_my_role
  FROM public.clan_members
  WHERE user_id = v_uid;

  IF v_clan IS NULL OR v_my_role NOT IN ('leader', 'officer') THEN
    RAISE EXCEPTION 'NOT_ALLOWED' USING ERRCODE = '42501';
  END IF;

  IF v_my_role = 'leader' THEN
    IF v_role NOT IN ('officer', 'trainer', 'member') THEN
      RAISE EXCEPTION 'INVALID_CLAN_ROLE' USING ERRCODE = 'P0001';
    END IF;
  ELSE
    -- deputy: only trainer / member
    IF v_role NOT IN ('trainer', 'member') THEN
      RAISE EXCEPTION 'NOT_ALLOWED' USING ERRCODE = '42501';
    END IF;
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

  -- Officer cannot change other officers
  IF v_my_role = 'officer' AND v_target_role = 'officer' THEN
    RAISE EXCEPTION 'NOT_ALLOWED' USING ERRCODE = '42501';
  END IF;

  UPDATE public.clan_members
  SET role = v_role
  WHERE clan_id = v_clan AND user_id = p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.set_clan_member_role(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_clan_member_role(UUID, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
