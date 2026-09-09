-- ============================================================
-- Clan join: applications only; only clan leader (creator) decides
-- ============================================================

CREATE OR REPLACE FUNCTION public.is_clan_leader(p_clan_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.clans c
    WHERE c.id = p_clan_id
      AND c.leader_id = auth.uid()
  );
$$;

REVOKE ALL ON FUNCTION public.is_clan_leader(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_clan_leader(UUID) TO authenticated;

-- Pending requests visible to applicant + leader only
DROP POLICY IF EXISTS "Join requests readable" ON public.clan_join_requests;
CREATE POLICY "Join requests readable"
  ON public.clan_join_requests
  FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_clan_leader(clan_id)
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
  v_leader UUID;
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

  SELECT leader_id INTO v_leader
  FROM public.clans
  WHERE id = v_clan;

  IF v_leader IS NULL OR v_leader <> v_uid THEN
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
  'Approve/reject clan join request — only clans.leader_id (creator/owner)';
