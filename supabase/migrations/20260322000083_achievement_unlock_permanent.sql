-- Permanent unlocks: soft-delete catalog, never revoke unlocked awards

-- 1) Admin "delete" only deactivates — keep rows + user_achievements
CREATE OR REPLACE FUNCTION public.admin_delete_achievement(p_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_old public.achievements;
BEGIN
  v_admin := public.require_admin('admin');
  SELECT * INTO v_old FROM public.achievements WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ACHIEVEMENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.achievements
  SET is_active = FALSE
  WHERE id = p_id;

  PERFORM public.write_admin_audit(
    v_admin,
    'delete_achievement',
    'achievement',
    p_id::TEXT,
    to_jsonb(v_old),
    jsonb_build_object('is_active', false, 'soft_deleted', true)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_achievement(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_achievement(UUID) TO authenticated;

-- 2) Sync must never revoke an unlock once granted
CREATE OR REPLACE FUNCTION public.sync_user_achievements(p_items JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  item JSONB;
  v_achievement UUID;
  v_progress INTEGER;
  v_unlocked BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  FOR item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_achievement := (item->>'achievement_id')::UUID;
    v_progress := GREATEST(0, COALESCE((item->>'progress')::INTEGER, 0));
    v_unlocked := COALESCE((item->>'unlocked')::BOOLEAN, FALSE);

    INSERT INTO public.user_achievements AS ua (
      user_id,
      achievement_id,
      progress,
      unlocked,
      unlocked_at
    )
    VALUES (
      v_uid,
      v_achievement,
      v_progress,
      v_unlocked,
      CASE WHEN v_unlocked THEN NOW() ELSE NULL END
    )
    ON CONFLICT (user_id, achievement_id) DO UPDATE
    SET
      progress = GREATEST(ua.progress, EXCLUDED.progress),
      unlocked = ua.unlocked OR EXCLUDED.unlocked,
      unlocked_at = CASE
        WHEN ua.unlocked THEN ua.unlocked_at
        WHEN EXCLUDED.unlocked THEN NOW()
        ELSE NULL
      END;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.sync_user_achievements(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sync_user_achievements(JSONB) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- Others can see unlocked awards (including soft-deleted catalog items)
DROP POLICY IF EXISTS "Users read own achievement progress"
  ON public.user_achievements;
DROP POLICY IF EXISTS "Unlocked achievements readable"
  ON public.user_achievements;
CREATE POLICY "Unlocked achievements readable"
  ON public.user_achievements
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id OR unlocked = TRUE);
