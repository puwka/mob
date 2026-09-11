-- player_level must include admin bonus_xp (same total as profiles.rating)

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
  v_bonus INTEGER;
  v_rating INTEGER;
  v_events INTEGER;
  v_xp INTEGER;
BEGIN
  SELECT games_played, wins, polygons_visited, bonus_xp, rating
  INTO v_games, v_wins, v_polygons, v_bonus, v_rating
  FROM public.profiles
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RETURN 1;
  END IF;

  SELECT COUNT(*)::INTEGER INTO v_events
  FROM public.event_participants
  WHERE user_id = p_user_id
    AND registration_status = 'registered';

  v_xp := public.compute_player_xp(v_games, v_wins, v_polygons, v_events)
    + COALESCE(v_bonus, 0);
  v_xp := GREATEST(0, v_xp, COALESCE(v_rating, 0));

  RETURN public.compute_player_level(v_xp);
END;
$$;
