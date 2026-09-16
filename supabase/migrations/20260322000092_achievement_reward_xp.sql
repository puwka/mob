-- Achievement XP rewards on unlock (all types)

ALTER TABLE public.achievements
  ADD COLUMN IF NOT EXISTS reward_xp INTEGER NOT NULL DEFAULT 100
    CHECK (reward_xp >= 0);

COMMENT ON COLUMN public.achievements.reward_xp IS
  'XP awarded once when the achievement is first unlocked (via bonus_xp)';

ALTER TABLE public.user_achievements
  ADD COLUMN IF NOT EXISTS reward_granted BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.user_achievements.reward_granted IS
  'True after reward_xp was added to profiles.bonus_xp';

-- Existing catalog: ensure a positive reward
UPDATE public.achievements
SET reward_xp = 100
WHERE reward_xp IS NULL OR reward_xp < 0;

CREATE OR REPLACE FUNCTION public.admin_list_achievements()
RETURNS SETOF public.achievements
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.require_admin('moderator');
  RETURN QUERY
  SELECT * FROM public.achievements
  ORDER BY type ASC, required_value ASC, title ASC;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_upsert_achievement(
  p_id UUID DEFAULT NULL,
  p_title TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_icon TEXT DEFAULT NULL,
  p_type TEXT DEFAULT NULL,
  p_required_value INTEGER DEFAULT NULL,
  p_is_active BOOLEAN DEFAULT NULL,
  p_reward_xp INTEGER DEFAULT NULL
)
RETURNS public.achievements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_old public.achievements;
  v_new public.achievements;
BEGIN
  v_admin := public.require_admin('moderator');

  IF p_type IS NOT NULL AND p_type NOT IN (
    'games_played',
    'wins',
    'polygons_visited',
    'rating',
    'events_count',
    'team_games',
    'organized_events',
    'organized_participants',
    'role_games',
    'messages_sent',
    'dating_likes',
    'profile_photos',
    'clan_joined',
    'events_attended_confirmed',
    'listings_published'
  ) THEN
    RAISE EXCEPTION 'INVALID_TYPE' USING ERRCODE = 'P0001';
  END IF;

  IF p_reward_xp IS NOT NULL AND p_reward_xp < 0 THEN
    RAISE EXCEPTION 'INVALID_REWARD_XP' USING ERRCODE = 'P0001';
  END IF;

  IF p_id IS NULL THEN
    IF p_title IS NULL OR p_type IS NULL OR p_required_value IS NULL THEN
      RAISE EXCEPTION 'MISSING_FIELDS' USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO public.achievements (
      title, description, icon, type, required_value, is_active, reward_xp
    ) VALUES (
      trim(p_title),
      COALESCE(p_description, ''),
      COALESCE(p_icon, 'award'),
      p_type,
      p_required_value,
      COALESCE(p_is_active, TRUE),
      COALESCE(p_reward_xp, 100)
    )
    RETURNING * INTO v_new;
    PERFORM public.write_admin_audit(
      v_admin, 'create_achievement', 'achievement', v_new.id::TEXT, NULL, to_jsonb(v_new)
    );
    RETURN v_new;
  END IF;

  SELECT * INTO v_old FROM public.achievements WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ACHIEVEMENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.achievements SET
    title = COALESCE(NULLIF(trim(p_title), ''), title),
    description = COALESCE(p_description, description),
    icon = COALESCE(p_icon, icon),
    type = COALESCE(p_type, type),
    required_value = COALESCE(p_required_value, required_value),
    is_active = COALESCE(p_is_active, is_active),
    reward_xp = COALESCE(p_reward_xp, reward_xp)
  WHERE id = p_id
  RETURNING * INTO v_new;

  PERFORM public.write_admin_audit(
    v_admin, 'update_achievement', 'achievement', p_id::TEXT, to_jsonb(v_old), to_jsonb(v_new)
  );
  RETURN v_new;
END;
$$;

-- Drop old signature (without reward_xp)
DROP FUNCTION IF EXISTS public.admin_upsert_achievement(
  UUID, TEXT, TEXT, TEXT, TEXT, INTEGER, BOOLEAN
);

REVOKE ALL ON FUNCTION public.admin_upsert_achievement(
  UUID, TEXT, TEXT, TEXT, TEXT, INTEGER, BOOLEAN, INTEGER
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_upsert_achievement(
  UUID, TEXT, TEXT, TEXT, TEXT, INTEGER, BOOLEAN, INTEGER
) TO authenticated;

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
  v_was_unlocked BOOLEAN;
  v_reward_granted BOOLEAN;
  v_reward INTEGER;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  FOR item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_achievement := (item->>'achievement_id')::UUID;
    v_progress := GREATEST(0, COALESCE((item->>'progress')::INTEGER, 0));
    v_unlocked := COALESCE((item->>'unlocked')::BOOLEAN, FALSE);

    SELECT ua.unlocked, COALESCE(ua.reward_granted, FALSE)
    INTO v_was_unlocked, v_reward_granted
    FROM public.user_achievements ua
    WHERE ua.user_id = v_uid
      AND ua.achievement_id = v_achievement;

    IF NOT FOUND THEN
      v_was_unlocked := FALSE;
      v_reward_granted := FALSE;
    END IF;

    INSERT INTO public.user_achievements AS ua (
      user_id,
      achievement_id,
      progress,
      unlocked,
      unlocked_at,
      reward_granted
    )
    VALUES (
      v_uid,
      v_achievement,
      v_progress,
      v_unlocked,
      CASE WHEN v_unlocked THEN NOW() ELSE NULL END,
      FALSE
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

    -- Grant XP once when unlocked (new unlock or catch-up for older unlocks)
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

NOTIFY pgrst, 'reload schema';
