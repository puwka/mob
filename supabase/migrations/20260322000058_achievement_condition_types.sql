-- ============================================================
-- Achievement condition types expansion + metrics RPC
-- ============================================================

ALTER TABLE public.achievements
  DROP CONSTRAINT IF EXISTS achievements_type_check;

ALTER TABLE public.achievements
  ADD CONSTRAINT achievements_type_check CHECK (
    type IN (
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
    )
  );

CREATE OR REPLACE FUNCTION public.admin_upsert_achievement(
  p_id UUID DEFAULT NULL,
  p_title TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_icon TEXT DEFAULT NULL,
  p_type TEXT DEFAULT NULL,
  p_required_value INTEGER DEFAULT NULL,
  p_is_active BOOLEAN DEFAULT NULL
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

  IF p_id IS NULL THEN
    IF p_title IS NULL OR p_type IS NULL OR p_required_value IS NULL THEN
      RAISE EXCEPTION 'MISSING_FIELDS' USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO public.achievements (
      title, description, icon, type, required_value, is_active
    ) VALUES (
      trim(p_title),
      COALESCE(p_description, ''),
      COALESCE(p_icon, 'award'),
      p_type,
      p_required_value,
      COALESCE(p_is_active, TRUE)
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
    is_active = COALESCE(p_is_active, is_active)
  WHERE id = p_id
  RETURNING * INTO v_new;

  PERFORM public.write_admin_audit(
    v_admin, 'update_achievement', 'achievement', p_id::TEXT, to_jsonb(v_old), to_jsonb(v_new)
  );
  RETURN v_new;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_upsert_achievement(
  UUID, TEXT, TEXT, TEXT, TEXT, INTEGER, BOOLEAN
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_upsert_achievement(
  UUID, TEXT, TEXT, TEXT, TEXT, INTEGER, BOOLEAN
) TO authenticated;

-- Live metrics for achievement evaluation (any authenticated reader)
CREATE OR REPLACE FUNCTION public.get_achievement_metrics(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile public.profiles%ROWTYPE;
  v_events_registered INTEGER := 0;
  v_events_confirmed INTEGER := 0;
  v_organized_events INTEGER := 0;
  v_organized_participants INTEGER := 0;
  v_messages INTEGER := 0;
  v_dating_likes INTEGER := 0;
  v_photos INTEGER := 0;
  v_clan INTEGER := 0;
  v_listings INTEGER := 0;
  v_team_games INTEGER := 0;
  v_role_games INTEGER := 0;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_USER' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_profile FROM public.profiles WHERE id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  SELECT COUNT(*)::INTEGER INTO v_events_registered
  FROM public.event_participants
  WHERE user_id = p_user_id
    AND registration_status = 'registered';

  SELECT COUNT(*)::INTEGER INTO v_events_confirmed
  FROM public.event_participants
  WHERE user_id = p_user_id
    AND attendance_status = 'confirmed';

  SELECT COUNT(*)::INTEGER INTO v_organized_events
  FROM public.events
  WHERE organizer_id = p_user_id
    AND status IN ('active', 'finished');

  SELECT COUNT(*)::INTEGER INTO v_organized_participants
  FROM public.event_participants ep
  JOIN public.events e ON e.id = ep.event_id
  WHERE e.organizer_id = p_user_id
    AND ep.registration_status = 'registered';

  SELECT COUNT(*)::INTEGER INTO v_messages
  FROM public.messages
  WHERE sender_id = p_user_id
    AND deleted_at IS NULL;

  SELECT COUNT(*)::INTEGER INTO v_dating_likes
  FROM public.dating_actions
  WHERE from_user_id = p_user_id
    AND action = 'like';

  SELECT COUNT(*)::INTEGER INTO v_photos
  FROM public.profile_photos
  WHERE user_id = p_user_id;

  SELECT CASE WHEN EXISTS (
    SELECT 1 FROM public.clan_members WHERE user_id = p_user_id
  ) THEN 1 ELSE 0 END INTO v_clan;

  SELECT COUNT(*)::INTEGER INTO v_listings
  FROM public.listings
  WHERE seller_id = p_user_id
    AND status IN ('active', 'sold');

  -- Team / role games: count confirmed attendances when profile has team/role set
  IF NULLIF(btrim(COALESCE(v_profile.team_name, '')), '') IS NOT NULL THEN
    v_team_games := GREATEST(v_profile.games_played, v_events_confirmed);
  ELSE
    v_team_games := 0;
  END IF;

  IF NULLIF(btrim(COALESCE(v_profile.game_role, '')), '') IS NOT NULL THEN
    v_role_games := GREATEST(v_profile.games_played, v_events_confirmed);
  ELSE
    v_role_games := 0;
  END IF;

  RETURN jsonb_build_object(
    'games_played', COALESCE(v_profile.games_played, 0),
    'wins', COALESCE(v_profile.wins, 0),
    'polygons_visited', COALESCE(v_profile.polygons_visited, 0),
    'rating', COALESCE(v_profile.rating, 0),
    'events_count', v_events_registered,
    'team_games', v_team_games,
    'organized_events', v_organized_events,
    'organized_participants', v_organized_participants,
    'role_games', v_role_games,
    'messages_sent', v_messages,
    'dating_likes', v_dating_likes,
    'profile_photos', v_photos,
    'clan_joined', v_clan,
    'events_attended_confirmed', v_events_confirmed,
    'listings_published', v_listings
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_achievement_metrics(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_achievement_metrics(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
