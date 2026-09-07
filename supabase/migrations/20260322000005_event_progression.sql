-- ============================================================
-- Stage 4: event-linked achievements + events count helper
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
      'events_count'
    )
  );

-- Count of event participations for a user (SECURITY INVOKER → RLS applies)
CREATE OR REPLACE FUNCTION public.get_user_events_count(p_user_id UUID)
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT COUNT(*)::INTEGER
  FROM public.event_participants
  WHERE user_id = p_user_id;
$$;

REVOKE ALL ON FUNCTION public.get_user_events_count(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_user_events_count(UUID) TO authenticated;

INSERT INTO public.achievements (title, description, icon, type, required_value)
VALUES
  ('Первое мероприятие', 'Записаться на 1 мероприятие', 'first_event', 'events_count', 1),
  ('Активист', 'Записаться на 5 мероприятий', 'activist', 'events_count', 5),
  ('Ветеран сообщества', 'Записаться на 10 мероприятий', 'community_veteran', 'events_count', 10)
ON CONFLICT (title) DO UPDATE
SET
  description = EXCLUDED.description,
  icon = EXCLUDED.icon,
  type = EXCLUDED.type,
  required_value = EXCLUDED.required_value;
