-- Admin grant / revoke user achievements (sticky against client sync)

ALTER TABLE public.user_achievements
  ADD COLUMN IF NOT EXISTS admin_override TEXT
    CHECK (admin_override IS NULL OR admin_override IN ('granted', 'revoked'));

COMMENT ON COLUMN public.user_achievements.admin_override IS
  'Admin sticky state: granted stays unlocked; revoked stays locked despite metrics/sync';

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
  v_reward_granted BOOLEAN;
  v_reward INTEGER;
  v_override TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  FOR item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_achievement := (item->>'achievement_id')::UUID;
    v_progress := GREATEST(0, COALESCE((item->>'progress')::INTEGER, 0));
    v_unlocked := COALESCE((item->>'unlocked')::BOOLEAN, FALSE);

    SELECT COALESCE(ua.reward_granted, FALSE), ua.admin_override
    INTO v_reward_granted, v_override
    FROM public.user_achievements ua
    WHERE ua.user_id = v_uid
      AND ua.achievement_id = v_achievement;

    IF NOT FOUND THEN
      v_reward_granted := FALSE;
      v_override := NULL;
    END IF;

    IF v_override = 'revoked' THEN
      v_unlocked := FALSE;
    ELSIF v_override = 'granted' THEN
      v_unlocked := TRUE;
    END IF;

    INSERT INTO public.user_achievements AS ua (
      user_id,
      achievement_id,
      progress,
      unlocked,
      unlocked_at,
      reward_granted,
      admin_override
    )
    VALUES (
      v_uid,
      v_achievement,
      v_progress,
      v_unlocked,
      CASE WHEN v_unlocked THEN NOW() ELSE NULL END,
      FALSE,
      NULL
    )
    ON CONFLICT (user_id, achievement_id) DO UPDATE
    SET
      progress = GREATEST(ua.progress, EXCLUDED.progress),
      unlocked = CASE
        WHEN ua.admin_override = 'revoked' THEN FALSE
        WHEN ua.admin_override = 'granted' THEN TRUE
        ELSE ua.unlocked OR EXCLUDED.unlocked
      END,
      unlocked_at = CASE
        WHEN ua.admin_override = 'revoked' THEN NULL
        WHEN ua.admin_override = 'granted' THEN COALESCE(ua.unlocked_at, NOW())
        WHEN ua.unlocked THEN ua.unlocked_at
        WHEN EXCLUDED.unlocked THEN NOW()
        ELSE NULL
      END;

    IF v_unlocked AND NOT COALESCE(v_reward_granted, FALSE) THEN
      SELECT COALESCE(a.reward_xp, 0)
      INTO v_reward
      FROM public.achievements a
      WHERE a.id = v_achievement;

      UPDATE public.user_achievements
      SET reward_granted = TRUE
      WHERE user_id = v_uid
        AND achievement_id = v_achievement
        AND reward_granted IS DISTINCT FROM TRUE;

      IF FOUND AND COALESCE(v_reward, 0) > 0 THEN
        UPDATE public.profiles
        SET bonus_xp = COALESCE(bonus_xp, 0) + v_reward
        WHERE id = v_uid;
      END IF;
    END IF;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.sync_user_achievements(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sync_user_achievements(JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_list_user_achievements(p_user_id UUID)
RETURNS TABLE (
  achievement_id UUID,
  title TEXT,
  description TEXT,
  icon TEXT,
  type TEXT,
  required_value INTEGER,
  reward_xp INTEGER,
  is_active BOOLEAN,
  progress INTEGER,
  unlocked BOOLEAN,
  unlocked_at TIMESTAMPTZ,
  admin_override TEXT,
  reward_granted BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.require_admin('moderator');

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  RETURN QUERY
  SELECT
    a.id,
    a.title,
    a.description,
    a.icon,
    a.type,
    a.required_value,
    COALESCE(a.reward_xp, 0),
    COALESCE(a.is_active, TRUE),
    COALESCE(ua.progress, 0),
    COALESCE(ua.unlocked, FALSE),
    ua.unlocked_at,
    ua.admin_override,
    COALESCE(ua.reward_granted, FALSE)
  FROM public.achievements a
  LEFT JOIN public.user_achievements ua
    ON ua.achievement_id = a.id
   AND ua.user_id = p_user_id
  WHERE COALESCE(a.is_active, TRUE) = TRUE
     OR ua.id IS NOT NULL
  ORDER BY
    COALESCE(ua.unlocked, FALSE) DESC,
    a.type ASC,
    a.required_value ASC,
    a.title ASC;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_grant_user_achievement(
  p_user_id UUID,
  p_achievement_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_ach public.achievements;
  v_was_unlocked BOOLEAN;
  v_reward_granted BOOLEAN;
  v_old JSONB;
BEGIN
  v_admin := public.require_admin('moderator');

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_ach FROM public.achievements WHERE id = p_achievement_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ACHIEVEMENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  SELECT to_jsonb(ua), ua.unlocked, COALESCE(ua.reward_granted, FALSE)
  INTO v_old, v_was_unlocked, v_reward_granted
  FROM public.user_achievements ua
  WHERE ua.user_id = p_user_id
    AND ua.achievement_id = p_achievement_id;

  IF NOT FOUND THEN
    v_was_unlocked := FALSE;
    v_reward_granted := FALSE;
    v_old := NULL;
  END IF;

  INSERT INTO public.user_achievements AS ua (
    user_id,
    achievement_id,
    progress,
    unlocked,
    unlocked_at,
    reward_granted,
    admin_override
  )
  VALUES (
    p_user_id,
    p_achievement_id,
    v_ach.required_value,
    TRUE,
    NOW(),
    FALSE,
    'granted'
  )
  ON CONFLICT (user_id, achievement_id) DO UPDATE
  SET
    progress = GREATEST(ua.progress, v_ach.required_value),
    unlocked = TRUE,
    unlocked_at = COALESCE(ua.unlocked_at, NOW()),
    admin_override = 'granted';

  IF NOT v_reward_granted AND COALESCE(v_ach.reward_xp, 0) > 0 THEN
    UPDATE public.user_achievements
    SET reward_granted = TRUE
    WHERE user_id = p_user_id
      AND achievement_id = p_achievement_id
      AND reward_granted IS DISTINCT FROM TRUE;

    IF FOUND THEN
      UPDATE public.profiles
      SET bonus_xp = COALESCE(bonus_xp, 0) + v_ach.reward_xp
      WHERE id = p_user_id;
    END IF;
  ELSIF v_reward_granted THEN
    UPDATE public.user_achievements
    SET reward_granted = TRUE
    WHERE user_id = p_user_id
      AND achievement_id = p_achievement_id;
  END IF;

  PERFORM public.write_admin_audit(
    v_admin,
    'grant_achievement',
    'user_achievement',
    p_user_id::TEXT || ':' || p_achievement_id::TEXT,
    v_old,
    jsonb_build_object(
      'user_id', p_user_id,
      'achievement_id', p_achievement_id,
      'title', v_ach.title,
      'admin_override', 'granted',
      'reward_xp', COALESCE(v_ach.reward_xp, 0)
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_revoke_user_achievement(
  p_user_id UUID,
  p_achievement_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_ach public.achievements;
  v_reward_granted BOOLEAN;
  v_old JSONB;
BEGIN
  v_admin := public.require_admin('moderator');

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_ach FROM public.achievements WHERE id = p_achievement_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ACHIEVEMENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  SELECT to_jsonb(ua), COALESCE(ua.reward_granted, FALSE)
  INTO v_old, v_reward_granted
  FROM public.user_achievements ua
  WHERE ua.user_id = p_user_id
    AND ua.achievement_id = p_achievement_id;

  IF NOT FOUND THEN
    -- Sticky revoke even if never unlocked, so sync cannot auto-grant
    INSERT INTO public.user_achievements (
      user_id,
      achievement_id,
      progress,
      unlocked,
      unlocked_at,
      reward_granted,
      admin_override
    ) VALUES (
      p_user_id,
      p_achievement_id,
      0,
      FALSE,
      NULL,
      FALSE,
      'revoked'
    );
  ELSE
    UPDATE public.user_achievements
    SET
      unlocked = FALSE,
      unlocked_at = NULL,
      admin_override = 'revoked',
      reward_granted = FALSE
    WHERE user_id = p_user_id
      AND achievement_id = p_achievement_id;

    IF v_reward_granted AND COALESCE(v_ach.reward_xp, 0) > 0 THEN
      UPDATE public.profiles
      SET bonus_xp = GREATEST(0, COALESCE(bonus_xp, 0) - v_ach.reward_xp)
      WHERE id = p_user_id;
    END IF;
  END IF;

  PERFORM public.write_admin_audit(
    v_admin,
    'revoke_achievement',
    'user_achievement',
    p_user_id::TEXT || ':' || p_achievement_id::TEXT,
    v_old,
    jsonb_build_object(
      'user_id', p_user_id,
      'achievement_id', p_achievement_id,
      'title', v_ach.title,
      'admin_override', 'revoked',
      'reward_clawback', CASE
        WHEN v_reward_granted THEN COALESCE(v_ach.reward_xp, 0)
        ELSE 0
      END
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_user_achievements(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_grant_user_achievement(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_revoke_user_achievement(UUID, UUID) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.admin_list_user_achievements(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_grant_user_achievement(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_revoke_user_achievement(UUID, UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
