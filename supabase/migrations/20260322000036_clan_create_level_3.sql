-- ============================================================
-- Creating a clan requires player level >= 3
-- Level curve must match Flutter LevelService:
--   xpRequiredForLevel(L) = 200 + (L - 1) * 75
-- ============================================================

CREATE OR REPLACE FUNCTION public.xp_required_for_level(p_level INTEGER)
RETURNS INTEGER
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_level < 1 THEN 200
    ELSE 200 + (p_level - 1) * 75
  END;
$$;

CREATE OR REPLACE FUNCTION public.compute_player_level(p_xp INTEGER)
RETURNS INTEGER
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_xp INTEGER := GREATEST(COALESCE(p_xp, 0), 0);
  v_level INTEGER := 1;
  v_threshold INTEGER := 0;
  v_next_cost INTEGER := public.xp_required_for_level(1);
BEGIN
  WHILE v_xp >= v_threshold + v_next_cost LOOP
    v_threshold := v_threshold + v_next_cost;
    v_level := v_level + 1;
    v_next_cost := public.xp_required_for_level(v_level);
  END LOOP;
  RETURN v_level;
END;
$$;

CREATE OR REPLACE FUNCTION public.player_level(p_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_games INTEGER;
  v_wins INTEGER;
  v_polygons INTEGER;
  v_events INTEGER;
  v_xp INTEGER;
BEGIN
  SELECT games_played, wins, polygons_visited
  INTO v_games, v_wins, v_polygons
  FROM public.profiles
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RETURN 1;
  END IF;

  SELECT COUNT(*)::INTEGER INTO v_events
  FROM public.event_participants
  WHERE user_id = p_user_id
    AND registration_status = 'registered';

  v_xp := public.compute_player_xp(v_games, v_wins, v_polygons, v_events);
  RETURN public.compute_player_level(v_xp);
END;
$$;

REVOKE ALL ON FUNCTION public.xp_required_for_level(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.xp_required_for_level(INTEGER) TO anon, authenticated;

REVOKE ALL ON FUNCTION public.compute_player_level(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.compute_player_level(INTEGER) TO anon, authenticated;

REVOKE ALL ON FUNCTION public.player_level(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.player_level(UUID) TO authenticated;

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
  v_level INTEGER;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  v_level := public.player_level(v_uid);
  IF v_level < 3 THEN
    RAISE EXCEPTION 'LEVEL_TOO_LOW' USING ERRCODE = 'P0001';
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

  SELECT id INTO v_conv
  FROM public.conversations
  WHERE type = 'clan' AND clan_id = v_clan AND clan_channel = 'general';

  IF v_conv IS NULL THEN
    INSERT INTO public.conversations (type, title, clan_id, clan_channel)
    VALUES ('clan', v_name, v_clan, 'general');
  END IF;

  PERFORM public.recompute_clan_rating(v_clan);
  RETURN v_clan;
END;
$$;

REVOKE ALL ON FUNCTION public.create_clan(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_clan(TEXT, TEXT, TEXT, TEXT) TO authenticated;

COMMENT ON FUNCTION public.create_clan(TEXT, TEXT, TEXT, TEXT) IS
  'Create clan — requires player level >= 3 (XP curve matches Flutter LevelService)';
