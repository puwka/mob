-- ============================================================
-- Organizer withdrawal requests → admin approval
-- ============================================================

CREATE TABLE IF NOT EXISTS public.organizer_withdrawal_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organizer_id UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  amount NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
  fee NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (fee >= 0),
  net_amount NUMERIC(12, 2) NOT NULL CHECK (net_amount > 0),
  payment_details TEXT NOT NULL CHECK (char_length(trim(payment_details)) BETWEEN 5 AND 1000),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  admin_note TEXT,
  reviewed_by UUID REFERENCES public.admin_users (id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  debit_transaction_id UUID REFERENCES public.organizer_transactions (id) ON DELETE SET NULL,
  refund_transaction_id UUID REFERENCES public.organizer_transactions (id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS organizer_withdrawal_requests_org_idx
  ON public.organizer_withdrawal_requests (organizer_id, created_at DESC);

CREATE INDEX IF NOT EXISTS organizer_withdrawal_requests_status_idx
  ON public.organizer_withdrawal_requests (status, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS organizer_withdrawal_one_pending_idx
  ON public.organizer_withdrawal_requests (organizer_id)
  WHERE status = 'pending';

ALTER TABLE public.organizer_withdrawal_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Organizers read own withdrawal requests"
  ON public.organizer_withdrawal_requests;
CREATE POLICY "Organizers read own withdrawal requests"
  ON public.organizer_withdrawal_requests
  FOR SELECT
  TO authenticated
  USING (organizer_id = auth.uid() AND public.is_organizer());

DROP POLICY IF EXISTS "Admins read withdrawal requests"
  ON public.organizer_withdrawal_requests;
CREATE POLICY "Admins read withdrawal requests"
  ON public.organizer_withdrawal_requests
  FOR SELECT
  TO authenticated
  USING (public.is_admin());

REVOKE INSERT, UPDATE, DELETE ON public.organizer_withdrawal_requests FROM authenticated;
GRANT SELECT ON public.organizer_withdrawal_requests TO authenticated;

INSERT INTO public.app_settings (key, value)
VALUES ('min_withdrawal_amount', '100')
ON CONFLICT (key) DO NOTHING;

-- ============================================================
-- Organizer: create withdrawal request (hold funds)
-- ============================================================

CREATE OR REPLACE FUNCTION public.request_organizer_withdrawal(
  p_amount NUMERIC,
  p_payment_details TEXT
)
RETURNS public.organizer_withdrawal_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_amount NUMERIC := ROUND(COALESCE(p_amount, 0), 2);
  v_details TEXT := trim(COALESCE(p_payment_details, ''));
  v_fee NUMERIC := 0;
  v_min NUMERIC := 100;
  v_total NUMERIC;
  v_balance NUMERIC;
  v_tx UUID;
  v_row public.organizer_withdrawal_requests;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_organizer() THEN
    RAISE EXCEPTION 'NOT_ORGANIZER' USING ERRCODE = '42501';
  END IF;

  IF v_amount <= 0 THEN
    RAISE EXCEPTION 'INVALID_AMOUNT' USING ERRCODE = 'P0001';
  END IF;

  IF char_length(v_details) < 5 OR char_length(v_details) > 1000 THEN
    RAISE EXCEPTION 'INVALID_PAYMENT_DETAILS' USING ERRCODE = 'P0001';
  END IF;

  BEGIN
    v_fee := GREATEST(
      0,
      COALESCE(NULLIF(public.get_app_setting('withdrawal_fee'), '')::NUMERIC, 0)
    );
  EXCEPTION WHEN OTHERS THEN
    v_fee := 0;
  END;

  BEGIN
    v_min := GREATEST(
      1,
      COALESCE(NULLIF(public.get_app_setting('min_withdrawal_amount'), '')::NUMERIC, 100)
    );
  EXCEPTION WHEN OTHERS THEN
    v_min := 100;
  END;

  IF v_amount < v_min THEN
    RAISE EXCEPTION 'AMOUNT_TOO_LOW' USING ERRCODE = 'P0001';
  END IF;

  v_total := ROUND(v_amount + v_fee, 2);

  IF EXISTS (
    SELECT 1 FROM public.organizer_withdrawal_requests
    WHERE organizer_id = v_uid AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'PENDING_EXISTS' USING ERRCODE = 'P0001';
  END IF;

  PERFORM public.ensure_organizer_wallet(v_uid);

  SELECT balance INTO v_balance
  FROM public.organizer_wallets
  WHERE organizer_id = v_uid
  FOR UPDATE;

  IF v_balance IS NULL OR v_balance < v_total THEN
    RAISE EXCEPTION 'INSUFFICIENT_BALANCE' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.organizer_wallets
  SET balance = v_balance - v_total, updated_at = NOW()
  WHERE organizer_id = v_uid;

  INSERT INTO public.organizer_transactions (
    organizer_id, amount, type, description
  ) VALUES (
    v_uid,
    -v_total,
    'withdrawal',
    'Заявка на вывод ' || v_amount::TEXT || ' CR'
      || CASE WHEN v_fee > 0 THEN ' (комиссия ' || v_fee::TEXT || ')' ELSE '' END
  )
  RETURNING id INTO v_tx;

  INSERT INTO public.organizer_withdrawal_requests (
    organizer_id,
    amount,
    fee,
    net_amount,
    payment_details,
    status,
    debit_transaction_id
  ) VALUES (
    v_uid,
    v_amount,
    v_fee,
    v_amount,
    v_details,
    'pending',
    v_tx
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.request_organizer_withdrawal(NUMERIC, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_organizer_withdrawal(NUMERIC, TEXT) TO authenticated;

-- ============================================================
-- Admin: list / approve / reject
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_list_withdrawal_requests(
  p_status TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  organizer_id UUID,
  organizer_nickname TEXT,
  organizer_phone TEXT,
  amount NUMERIC,
  fee NUMERIC,
  net_amount NUMERIC,
  payment_details TEXT,
  status TEXT,
  admin_note TEXT,
  reviewed_by UUID,
  reviewer_phone TEXT,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  balance NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.require_perm('economy_view');

  RETURN QUERY
  SELECT
    r.id,
    r.organizer_id,
    p.nickname,
    p.phone,
    r.amount,
    r.fee,
    r.net_amount,
    r.payment_details,
    r.status,
    r.admin_note,
    r.reviewed_by,
    a.phone,
    r.reviewed_at,
    r.created_at,
    r.updated_at,
    COALESCE(w.balance, 0)
  FROM public.organizer_withdrawal_requests r
  JOIN public.profiles p ON p.id = r.organizer_id
  LEFT JOIN public.admin_users a ON a.id = r.reviewed_by
  LEFT JOIN public.organizer_wallets w ON w.organizer_id = r.organizer_id
  WHERE (p_status IS NULL OR p_status = '' OR r.status = p_status)
  ORDER BY
    CASE r.status WHEN 'pending' THEN 0 ELSE 1 END,
    r.created_at DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 50), 200))
  OFFSET GREATEST(0, COALESCE(p_offset, 0));
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_withdrawal_requests(TEXT, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_withdrawal_requests(TEXT, INTEGER, INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_approve_withdrawal(
  p_id UUID,
  p_note TEXT DEFAULT NULL
)
RETURNS public.organizer_withdrawal_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_row public.organizer_withdrawal_requests;
BEGIN
  v_admin := public.require_perm('economy_adjust');

  SELECT * INTO v_row
  FROM public.organizer_withdrawal_requests
  WHERE id = p_id
  FOR UPDATE;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  IF v_row.status <> 'pending' THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.organizer_withdrawal_requests
  SET
    status = 'approved',
    admin_note = NULLIF(trim(COALESCE(p_note, '')), ''),
    reviewed_by = v_admin,
    reviewed_at = NOW(),
    updated_at = NOW()
  WHERE id = p_id
  RETURNING * INTO v_row;

  PERFORM public.write_admin_audit(
    v_admin,
    'approve_withdrawal',
    'withdrawal_request',
    p_id::TEXT,
    jsonb_build_object('status', 'pending'),
    jsonb_build_object(
      'status', 'approved',
      'amount', v_row.amount,
      'organizer_id', v_row.organizer_id,
      'note', v_row.admin_note
    )
  );

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_approve_withdrawal(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_approve_withdrawal(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_reject_withdrawal(
  p_id UUID,
  p_note TEXT DEFAULT NULL
)
RETURNS public.organizer_withdrawal_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_row public.organizer_withdrawal_requests;
  v_balance NUMERIC;
  v_refund NUMERIC;
  v_tx UUID;
BEGIN
  v_admin := public.require_perm('economy_adjust');

  SELECT * INTO v_row
  FROM public.organizer_withdrawal_requests
  WHERE id = p_id
  FOR UPDATE;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  IF v_row.status <> 'pending' THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING ERRCODE = 'P0001';
  END IF;

  v_refund := ROUND(v_row.amount + v_row.fee, 2);

  PERFORM public.ensure_organizer_wallet(v_row.organizer_id);

  SELECT balance INTO v_balance
  FROM public.organizer_wallets
  WHERE organizer_id = v_row.organizer_id
  FOR UPDATE;

  UPDATE public.organizer_wallets
  SET balance = COALESCE(v_balance, 0) + v_refund, updated_at = NOW()
  WHERE organizer_id = v_row.organizer_id;

  INSERT INTO public.organizer_transactions (
    organizer_id, amount, type, description
  ) VALUES (
    v_row.organizer_id,
    v_refund,
    'refund',
    'Возврат по отклонённой заявке на вывод'
  )
  RETURNING id INTO v_tx;

  UPDATE public.organizer_withdrawal_requests
  SET
    status = 'rejected',
    admin_note = NULLIF(trim(COALESCE(p_note, '')), ''),
    reviewed_by = v_admin,
    reviewed_at = NOW(),
    refund_transaction_id = v_tx,
    updated_at = NOW()
  WHERE id = p_id
  RETURNING * INTO v_row;

  PERFORM public.write_admin_audit(
    v_admin,
    'reject_withdrawal',
    'withdrawal_request',
    p_id::TEXT,
    jsonb_build_object('status', 'pending'),
    jsonb_build_object(
      'status', 'rejected',
      'amount', v_row.amount,
      'organizer_id', v_row.organizer_id,
      'refund', v_refund,
      'note', v_row.admin_note
    )
  );

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_reject_withdrawal(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_reject_withdrawal(UUID, TEXT) TO authenticated;
