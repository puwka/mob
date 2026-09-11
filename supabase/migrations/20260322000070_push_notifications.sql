-- ============================================================
-- System push: device tokens + dispatch queue (FCM via Edge Function)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.user_push_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  token TEXT NOT NULL,
  platform TEXT NOT NULL CHECK (platform IN ('android', 'ios', 'web')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT user_push_tokens_token_uniq UNIQUE (token)
);

CREATE INDEX IF NOT EXISTS user_push_tokens_user_idx
  ON public.user_push_tokens (user_id);

ALTER TABLE public.user_push_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Push tokens select own" ON public.user_push_tokens;
CREATE POLICY "Push tokens select own"
  ON public.user_push_tokens
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Push tokens insert own" ON public.user_push_tokens;
CREATE POLICY "Push tokens insert own"
  ON public.user_push_tokens
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Push tokens update own" ON public.user_push_tokens;
CREATE POLICY "Push tokens update own"
  ON public.user_push_tokens
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Push tokens delete own" ON public.user_push_tokens;
CREATE POLICY "Push tokens delete own"
  ON public.user_push_tokens
  FOR DELETE
  TO authenticated
  USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.upsert_push_token(
  p_token TEXT,
  p_platform TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_platform TEXT := lower(btrim(COALESCE(p_platform, '')));
  v_token TEXT := btrim(COALESCE(p_token, ''));
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;
  IF v_token = '' THEN
    RAISE EXCEPTION 'INVALID_TOKEN' USING ERRCODE = 'P0001';
  END IF;
  IF v_platform NOT IN ('android', 'ios', 'web') THEN
    RAISE EXCEPTION 'INVALID_PLATFORM' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.user_push_tokens (user_id, token, platform)
  VALUES (v_uid, v_token, v_platform)
  ON CONFLICT (token) DO UPDATE
  SET
    user_id = EXCLUDED.user_id,
    platform = EXCLUDED.platform,
    updated_at = NOW();
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_push_token(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_push_token(TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_push_token(p_token TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.user_push_tokens
  WHERE user_id = v_uid
    AND token = btrim(COALESCE(p_token, ''));
END;
$$;

REVOKE ALL ON FUNCTION public.delete_push_token(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_push_token(TEXT) TO authenticated;

-- Queue of push payloads for Edge Function (service role reads/updates)
CREATE TABLE IF NOT EXISTS public.push_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  source TEXT NOT NULL CHECK (source IN ('user_notifications', 'dating_notifications')),
  source_id UUID NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL DEFAULT '',
  data JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processed_at TIMESTAMPTZ,
  error TEXT
);

CREATE INDEX IF NOT EXISTS push_jobs_pending_idx
  ON public.push_jobs (created_at ASC)
  WHERE processed_at IS NULL;

ALTER TABLE public.push_jobs ENABLE ROW LEVEL SECURITY;
-- No policies for authenticated: only service role / SECURITY DEFINER

CREATE OR REPLACE FUNCTION public.enqueue_push_job(
  p_user_id UUID,
  p_source TEXT,
  p_source_id UUID,
  p_title TEXT,
  p_body TEXT,
  p_data JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO public.push_jobs (
    user_id, source, source_id, title, body, data
  ) VALUES (
    p_user_id, p_source, p_source_id,
    COALESCE(NULLIF(btrim(p_title), ''), 'Уведомление'),
    COALESCE(p_body, ''),
    COALESCE(p_data, '{}'::jsonb)
  )
  RETURNING id INTO v_id;

  -- Best-effort HTTP dispatch (pg_net). Configure URL/secret once:
  --   INSERT INTO public.push_dispatch_config(edge_url, hook_secret, enabled)
  --   VALUES ('https://PROJECT.supabase.co/functions/v1/send-push', 'YOUR_SECRET', true)
  --   ON CONFLICT (id) DO UPDATE SET ...
  PERFORM public.try_dispatch_push_job(v_id);

  RETURN v_id;
END;
$$;

CREATE TABLE IF NOT EXISTS public.push_dispatch_config (
  id INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  edge_url TEXT,
  hook_secret TEXT,
  enabled BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public.push_dispatch_config (id, enabled)
VALUES (1, FALSE)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.push_dispatch_config ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.try_dispatch_push_job(p_job_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_url TEXT;
  v_secret TEXT;
  v_enabled BOOLEAN;
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
    RETURN;
  END IF;

  BEGIN
    PERFORM net.http_post(
      url := btrim(v_url),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-push-secret', btrim(v_secret)
      ),
      body := jsonb_build_object('job_id', p_job_id),
      timeout_milliseconds := 5000
    );
  EXCEPTION
    WHEN undefined_function THEN
      NULL; -- pg_net not installed
    WHEN OTHERS THEN
      NULL; -- never break notification inserts
  END;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_enqueue_user_notification_push()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.enqueue_push_job(
    NEW.user_id,
    'user_notifications',
    NEW.id,
    NEW.title,
    NEW.body,
    jsonb_build_object(
      'kind', NEW.kind,
      'notification_id', NEW.id::TEXT,
      'event_id', COALESCE(NEW.event_id::TEXT, ''),
      'conversation_id', COALESCE(NEW.conversation_id::TEXT, ''),
      'actor_id', COALESCE(NEW.actor_id::TEXT, '')
    )
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS user_notifications_enqueue_push ON public.user_notifications;
CREATE TRIGGER user_notifications_enqueue_push
  AFTER INSERT OR UPDATE OF title, body, created_at, seen_at
  ON public.user_notifications
  FOR EACH ROW
  WHEN (NEW.seen_at IS NULL)
  EXECUTE PROCEDURE public.trg_enqueue_user_notification_push();

CREATE OR REPLACE FUNCTION public.trg_enqueue_dating_notification_push()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_nick TEXT;
  v_title TEXT;
  v_body TEXT;
BEGIN
  SELECT COALESCE(NULLIF(btrim(nickname), ''), 'Игрок')
  INTO v_nick
  FROM public.profiles
  WHERE id = NEW.from_user_id;

  IF NEW.kind = 'match' THEN
    v_title := 'Новое совпадение';
    v_body := 'Вы понравились друг другу с ' || COALESCE(v_nick, 'игроком');
  ELSE
    v_title := 'Вам поставили лайк';
    v_body := COALESCE(v_nick, 'Кто-то') || ' лайкнул вас в дейтинге';
  END IF;

  PERFORM public.enqueue_push_job(
    NEW.user_id,
    'dating_notifications',
    NEW.id,
    v_title,
    v_body,
    jsonb_build_object(
      'kind', NEW.kind,
      'notification_id', NEW.id::TEXT,
      'from_user_id', NEW.from_user_id::TEXT,
      'conversation_id', COALESCE(NEW.conversation_id::TEXT, ''),
      'match_id', COALESCE(NEW.match_id::TEXT, '')
    )
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS dating_notifications_enqueue_push ON public.dating_notifications;
CREATE TRIGGER dating_notifications_enqueue_push
  AFTER INSERT ON public.dating_notifications
  FOR EACH ROW
  WHEN (NEW.seen_at IS NULL)
  EXECUTE PROCEDURE public.trg_enqueue_dating_notification_push();

COMMENT ON TABLE public.user_push_tokens IS 'FCM device tokens for system push notifications';
COMMENT ON TABLE public.push_jobs IS 'Outbox for Edge Function send-push (FCM HTTP v1)';
COMMENT ON TABLE public.push_dispatch_config IS 'Enable pg_net calls to send-push; set edge_url + hook_secret';
