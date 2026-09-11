-- ============================================================
-- Event city normalize + client-callable push drain (no pg_cron)
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pg_net;

-- Normalize city for matching: "г. Москва" / "Москва" / "москва" → "москва"
CREATE OR REPLACE FUNCTION public.normalize_city(p_city TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT lower(
    btrim(
      regexp_replace(
        regexp_replace(
          coalesce(p_city, ''),
          '^\s*(г\.?|город|пос\.?|пгт\.?)\s+',
          '',
          'i'
        ),
        '\s+',
        ' ',
        'g'
      )
    )
  );
$$;

CREATE OR REPLACE FUNCTION public.emit_event_created_notifications(
  p_event_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event public.events%ROWTYPE;
  v_city TEXT;
  r RECORD;
BEGIN
  SELECT * INTO v_event FROM public.events WHERE id = p_event_id;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF v_event.status <> 'active' THEN
    RETURN;
  END IF;

  v_city := public.normalize_city(v_event.city);
  IF v_city = '' THEN
    RETURN;
  END IF;

  FOR r IN
    SELECT p.id
    FROM public.profiles p
    WHERE p.status = 'active'
      AND public.normalize_city(p.city) = v_city
      AND p.id <> v_event.organizer_id
  LOOP
    INSERT INTO public.user_notifications (
      user_id, kind, title, body, event_id, actor_id
    ) VALUES (
      r.id,
      'event_created',
      'Новая игра в вашем городе',
      left(v_event.title, 120),
      v_event.id,
      v_event.organizer_id
    );
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.try_dispatch_push_job(p_job_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, net, extensions
AS $$
DECLARE
  v_url TEXT;
  v_secret TEXT;
  v_enabled BOOLEAN;
  v_request_id BIGINT;
BEGIN
  SELECT edge_url, hook_secret, enabled
  INTO v_url, v_secret, v_enabled
  FROM public.push_dispatch_config
  WHERE id = 1;

  IF NOT COALESCE(v_enabled, FALSE)
     OR v_url IS NULL
     OR btrim(v_url) = ''
     OR v_secret IS NULL
     OR btrim(v_secret) = '' THEN
    UPDATE public.push_jobs
    SET error = COALESCE(error, 'dispatch_disabled')
    WHERE id = p_job_id
      AND processed_at IS NULL
      AND error IS NULL;
    RETURN;
  END IF;

  BEGIN
    SELECT net.http_post(
      url := btrim(v_url),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-push-secret', btrim(v_secret)
      ),
      body := jsonb_build_object('job_id', p_job_id),
      timeout_milliseconds := 10000
    ) INTO v_request_id;
  EXCEPTION
    WHEN undefined_function THEN
      UPDATE public.push_jobs
      SET error = 'pg_net_missing'
      WHERE id = p_job_id AND processed_at IS NULL;
    WHEN OTHERS THEN
      UPDATE public.push_jobs
      SET error = left('dispatch_error: ' || SQLERRM, 500)
      WHERE id = p_job_id AND processed_at IS NULL;
  END;
END;
$$;

-- Any logged-in client can flush the outbox (secret stays server-side).
CREATE OR REPLACE FUNCTION public.request_push_drain()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, net, extensions
AS $$
DECLARE
  v_url TEXT;
  v_secret TEXT;
  v_enabled BOOLEAN;
  v_pending INTEGER := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT COUNT(*)::INTEGER INTO v_pending
  FROM public.push_jobs
  WHERE processed_at IS NULL;

  IF v_pending = 0 THEN
    RETURN 0;
  END IF;

  SELECT edge_url, hook_secret, enabled
  INTO v_url, v_secret, v_enabled
  FROM public.push_dispatch_config
  WHERE id = 1;

  IF NOT COALESCE(v_enabled, FALSE)
     OR v_url IS NULL
     OR btrim(v_url) = ''
     OR v_secret IS NULL
     OR btrim(v_secret) = '' THEN
    RETURN v_pending;
  END IF;

  BEGIN
    PERFORM net.http_post(
      url := btrim(v_url),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-push-secret', btrim(v_secret)
      ),
      body := '{"mode":"drain"}'::jsonb,
      timeout_milliseconds := 15000
    );
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;

  RETURN v_pending;
END;
$$;

REVOKE ALL ON FUNCTION public.request_push_drain() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_push_drain() TO authenticated;
