-- Rename side display labels: light/dark → green/red team

CREATE OR REPLACE FUNCTION public.submit_event_report(
  p_event_id UUID,
  p_winner TEXT,
  p_score_light INTEGER,
  p_score_dark INTEGER
)
RETURNS public.events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_event public.events%ROWTYPE;
  v_winner TEXT := lower(btrim(COALESCE(p_winner, '')));
  v_payload JSONB;
  v_text TEXT;
  v_winner_label TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_event
  FROM public.events
  WHERE id = p_event_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF NOT public.is_event_manager(p_event_id, v_uid) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF v_event.status <> 'finished' THEN
    RAISE EXCEPTION 'EVENT_NOT_FINISHED' USING ERRCODE = 'P0001';
  END IF;

  IF v_event.report_submitted_at IS NOT NULL THEN
    RAISE EXCEPTION 'REPORT_ALREADY_SUBMITTED' USING ERRCODE = 'P0001';
  END IF;

  IF v_winner NOT IN ('light', 'dark', 'draw') THEN
    RAISE EXCEPTION 'INVALID_WINNER' USING ERRCODE = 'P0001';
  END IF;

  IF p_score_light IS NULL OR p_score_dark IS NULL
     OR p_score_light < 0 OR p_score_dark < 0 THEN
    RAISE EXCEPTION 'INVALID_SCORE' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.events
  SET report_winner = v_winner,
      report_score_light = p_score_light,
      report_score_dark = p_score_dark,
      report_submitted_at = NOW(),
      updated_at = NOW()
  WHERE id = p_event_id
  RETURNING * INTO v_event;

  v_winner_label := CASE v_winner
    WHEN 'light' THEN 'Зелёная команда'
    WHEN 'dark' THEN 'Красная команда'
    ELSE 'Ничья'
  END;

  v_payload := jsonb_build_object(
    'title', 'Итоги игры',
    'event_title', v_event.title,
    'winner', v_winner,
    'winner_label', v_winner_label,
    'score_light', p_score_light,
    'score_dark', p_score_dark
  );

  v_text := 'Итоги: ' || v_winner_label
         || ' · ' || p_score_light::TEXT || ':' || p_score_dark::TEXT;

  PERFORM public.ensure_event_chat(p_event_id);
  PERFORM public.post_event_chat_message(
    p_event_id,
    v_uid,
    'event_report',
    v_text,
    v_payload
  );

  RETURN v_event;
END;
$$;

NOTIFY pgrst, 'reload schema';
