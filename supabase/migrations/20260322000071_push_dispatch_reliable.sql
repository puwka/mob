-- ============================================================
-- Reliable push dispatch via pg_net (no pg_cron dependency)
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pg_net;

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

COMMENT ON FUNCTION public.try_dispatch_push_job(UUID) IS
  'Calls Edge Function send-push via pg_net; logs failures on push_jobs.error';
