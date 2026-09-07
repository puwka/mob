-- ============================================================
-- Organizer economy: wallets, transactions, attendance rewards
-- ============================================================

-- 1) App settings (reward amount, etc.)
CREATE TABLE IF NOT EXISTS public.app_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public.app_settings (key, value)
VALUES ('organizer_attendance_reward', '100')
ON CONFLICT (key) DO NOTHING;

ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated can read app settings" ON public.app_settings;
CREATE POLICY "Authenticated can read app settings"
  ON public.app_settings
  FOR SELECT
  TO authenticated
  USING (true);

REVOKE INSERT, UPDATE, DELETE ON public.app_settings FROM authenticated;
GRANT SELECT ON public.app_settings TO authenticated;

-- 2) Organizer wallets
CREATE TABLE IF NOT EXISTS public.organizer_wallets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organizer_id UUID NOT NULL UNIQUE REFERENCES public.profiles (id) ON DELETE CASCADE,
  balance NUMERIC(14, 2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
  currency TEXT NOT NULL DEFAULT 'credits',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS organizer_wallets_organizer_idx
  ON public.organizer_wallets (organizer_id);

ALTER TABLE public.organizer_wallets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Organizer reads own wallet" ON public.organizer_wallets;
CREATE POLICY "Organizer reads own wallet"
  ON public.organizer_wallets
  FOR SELECT
  TO authenticated
  USING (organizer_id = auth.uid() AND public.is_organizer());

REVOKE INSERT, UPDATE, DELETE ON public.organizer_wallets FROM authenticated;
GRANT SELECT ON public.organizer_wallets TO authenticated;

CREATE OR REPLACE FUNCTION public.set_wallet_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS organizer_wallets_set_updated_at ON public.organizer_wallets;
CREATE TRIGGER organizer_wallets_set_updated_at
  BEFORE UPDATE ON public.organizer_wallets
  FOR EACH ROW
  EXECUTE PROCEDURE public.set_wallet_updated_at();

-- 3) Transactions
CREATE TABLE IF NOT EXISTS public.organizer_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organizer_id UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  event_id UUID REFERENCES public.events (id) ON DELETE SET NULL,
  participant_id UUID REFERENCES public.event_participants (id) ON DELETE SET NULL,
  amount NUMERIC(14, 2) NOT NULL,
  type TEXT NOT NULL
    CHECK (type IN ('attendance_reward', 'withdrawal', 'bonus', 'refund', 'manual_adjustment')),
  description TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS organizer_transactions_org_idx
  ON public.organizer_transactions (organizer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS organizer_transactions_event_idx
  ON public.organizer_transactions (event_id);

-- One attendance reward per participant row (prevents double pay)
CREATE UNIQUE INDEX IF NOT EXISTS organizer_tx_attendance_unique
  ON public.organizer_transactions (event_id, participant_id)
  WHERE type = 'attendance_reward' AND participant_id IS NOT NULL;

ALTER TABLE public.organizer_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Organizer reads own transactions" ON public.organizer_transactions;
CREATE POLICY "Organizer reads own transactions"
  ON public.organizer_transactions
  FOR SELECT
  TO authenticated
  USING (organizer_id = auth.uid() AND public.is_organizer());

REVOKE INSERT, UPDATE, DELETE ON public.organizer_transactions FROM authenticated;
GRANT SELECT ON public.organizer_transactions TO authenticated;

-- 4) Ensure wallet helper
CREATE OR REPLACE FUNCTION public.ensure_organizer_wallet(p_organizer_id UUID)
RETURNS public.organizer_wallets
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.organizer_wallets;
BEGIN
  INSERT INTO public.organizer_wallets (organizer_id)
  VALUES (p_organizer_id)
  ON CONFLICT (organizer_id) DO NOTHING;

  SELECT * INTO v_row
  FROM public.organizer_wallets
  WHERE organizer_id = p_organizer_id;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_organizer_wallet(UUID) FROM PUBLIC;

-- 5) Admin role assignment also creates/removes wallet
CREATE OR REPLACE FUNCTION public.admin_set_app_role(
  p_user_id UUID,
  p_role TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_role IS NULL OR p_role NOT IN ('user', 'organizer') THEN
    RAISE EXCEPTION 'INVALID_ROLE' USING ERRCODE = 'P0001';
  END IF;

  IF auth.role() = 'authenticated' THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  UPDATE public.profiles
  SET role = p_role
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF p_role = 'organizer' THEN
    PERFORM public.ensure_organizer_wallet(p_user_id);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_app_role(UUID, TEXT) FROM PUBLIC;

-- Backfill wallets for existing organizers
INSERT INTO public.organizer_wallets (organizer_id)
SELECT id FROM public.profiles WHERE role = 'organizer'
ON CONFLICT (organizer_id) DO NOTHING;

-- 6) Confirm attendance + reward (atomic)
CREATE OR REPLACE FUNCTION public.confirm_event_attendance(
  p_event_id UUID,
  p_public_qr_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_event public.events%ROWTYPE;
  v_user public.profiles%ROWTYPE;
  v_part public.event_participants%ROWTYPE;
  v_wallet public.organizer_wallets%ROWTYPE;
  v_reward NUMERIC(14, 2);
  v_setting TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_organizer() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_event
  FROM public.events
  WHERE id = p_event_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_event.organizer_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'NOT_EVENT_OWNER' USING ERRCODE = '42501';
  END IF;

  IF v_event.status = 'finished' THEN
    RAISE EXCEPTION 'EVENT_FINISHED' USING ERRCODE = 'P0001';
  END IF;

  IF v_event.status = 'cancelled' THEN
    RAISE EXCEPTION 'EVENT_CANCELLED' USING ERRCODE = 'P0001';
  END IF;

  IF v_event.status <> 'active' THEN
    RAISE EXCEPTION 'EVENT_NOT_ACTIVE' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_user
  FROM public.profiles
  WHERE public_qr_id = p_public_qr_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_part
  FROM public.event_participants
  WHERE event_id = p_event_id
    AND user_id = v_user.id
  FOR UPDATE;

  IF NOT FOUND OR v_part.registration_status <> 'registered' THEN
    RAISE EXCEPTION 'NOT_REGISTERED' USING ERRCODE = 'P0001';
  END IF;

  IF v_part.attendance_status = 'confirmed' THEN
    RAISE EXCEPTION 'ALREADY_CONFIRMED' USING ERRCODE = 'P0001';
  END IF;

  SELECT value INTO v_setting
  FROM public.app_settings
  WHERE key = 'organizer_attendance_reward';

  v_reward := COALESCE(NULLIF(v_setting, '')::NUMERIC, 100);
  IF v_reward < 0 THEN
    v_reward := 0;
  END IF;

  UPDATE public.event_participants
  SET
    attendance_status = 'confirmed',
    attended_at = NOW(),
    confirmed_by = v_uid
  WHERE id = v_part.id
    AND attendance_status = 'not_confirmed'
  RETURNING * INTO v_part;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ALREADY_CONFIRMED' USING ERRCODE = 'P0001';
  END IF;

  v_wallet := public.ensure_organizer_wallet(v_uid);

  INSERT INTO public.organizer_transactions (
    organizer_id, event_id, participant_id, amount, type, description
  )
  VALUES (
    v_uid,
    v_event.id,
    v_part.id,
    v_reward,
    'attendance_reward',
    'Подтверждение: ' || v_user.nickname || ' · ' || v_event.title
  );

  UPDATE public.organizer_wallets
  SET balance = balance + v_reward
  WHERE organizer_id = v_uid
  RETURNING * INTO v_wallet;

  RETURN jsonb_build_object(
    'participant_id', v_part.id,
    'user_id', v_user.id,
    'nickname', v_user.nickname,
    'city', v_user.city,
    'avatar_url', v_user.avatar_url,
    'event_id', v_event.id,
    'event_title', v_event.title,
    'attended_at', v_part.attended_at,
    'reward_amount', v_reward,
    'balance', v_wallet.balance,
    'currency', v_wallet.currency
  );
END;
$$;

REVOKE ALL ON FUNCTION public.confirm_event_attendance(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.confirm_event_attendance(UUID, UUID) TO authenticated;

-- 7) Organizer dashboard stats (own data only)
CREATE OR REPLACE FUNCTION public.organizer_dashboard_stats()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_events INTEGER;
  v_participants INTEGER;
  v_today INTEGER;
  v_balance NUMERIC(14, 2);
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_organizer() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  SELECT COUNT(*)::INTEGER INTO v_events
  FROM public.events
  WHERE organizer_id = v_uid;

  SELECT COUNT(*)::INTEGER INTO v_participants
  FROM public.event_participants ep
  JOIN public.events e ON e.id = ep.event_id
  WHERE e.organizer_id = v_uid
    AND ep.registration_status = 'registered';

  SELECT COUNT(*)::INTEGER INTO v_today
  FROM public.event_participants ep
  JOIN public.events e ON e.id = ep.event_id
  WHERE e.organizer_id = v_uid
    AND ep.attendance_status = 'confirmed'
    AND ep.attended_at::date = CURRENT_DATE;

  SELECT COALESCE(w.balance, 0) INTO v_balance
  FROM public.organizer_wallets w
  WHERE w.organizer_id = v_uid;

  IF v_balance IS NULL THEN
    v_balance := 0;
  END IF;

  RETURN jsonb_build_object(
    'events_count', v_events,
    'participants_count', v_participants,
    'confirmed_today', v_today,
    'balance', v_balance
  );
END;
$$;

REVOKE ALL ON FUNCTION public.organizer_dashboard_stats() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.organizer_dashboard_stats() TO authenticated;

-- Realtime (optional)
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.organizer_wallets;
  EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.organizer_transactions;
  EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL;
  END;
END $$;
