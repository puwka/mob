-- ============================================================
-- Admin boost listing → top of feed + visual promo highlight
-- ============================================================

ALTER TABLE public.listings
  ADD COLUMN IF NOT EXISTS boosted_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS listings_boosted_at_idx
  ON public.listings (is_promoted DESC, boosted_at DESC NULLS LAST, created_at DESC);

-- Existing promos get a sort key
UPDATE public.listings
SET boosted_at = COALESCE(boosted_at, promoted_until, updated_at, created_at)
WHERE is_promoted = TRUE
  AND boosted_at IS NULL;

CREATE OR REPLACE FUNCTION public.admin_boost_listing(
  p_id UUID,
  p_days INTEGER DEFAULT NULL
)
RETURNS public.listings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_old public.listings;
  v_new public.listings;
BEGIN
  v_admin := public.require_admin('moderator');

  SELECT * INTO v_old FROM public.listings WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'LISTING_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF p_days IS NOT NULL AND p_days < 1 THEN
    RAISE EXCEPTION 'INVALID_DAYS' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.listings SET
    is_promoted = TRUE,
    promoted_until = CASE
      WHEN p_days IS NULL THEN NULL
      ELSE NOW() + make_interval(days => p_days)
    END,
    boosted_at = NOW(),
    updated_at = NOW()
  WHERE id = p_id
  RETURNING * INTO v_new;

  PERFORM public.write_admin_audit(
    v_admin,
    'boost_listing',
    'listing',
    p_id::TEXT,
    to_jsonb(v_old),
    to_jsonb(v_new)
  );

  RETURN v_new;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_unboost_listing(p_id UUID)
RETURNS public.listings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_old public.listings;
  v_new public.listings;
BEGIN
  v_admin := public.require_admin('moderator');

  SELECT * INTO v_old FROM public.listings WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'LISTING_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.listings SET
    is_promoted = FALSE,
    promoted_until = NULL,
    boosted_at = NULL,
    updated_at = NOW()
  WHERE id = p_id
  RETURNING * INTO v_new;

  PERFORM public.write_admin_audit(
    v_admin,
    'unboost_listing',
    'listing',
    p_id::TEXT,
    to_jsonb(v_old),
    to_jsonb(v_new)
  );

  RETURN v_new;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_boost_listing(UUID, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_boost_listing(UUID, INTEGER) TO authenticated;

REVOKE ALL ON FUNCTION public.admin_unboost_listing(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_unboost_listing(UUID) TO authenticated;

-- Keep upsert in sync when promote flags change
CREATE OR REPLACE FUNCTION public.admin_upsert_listing(
  p_id UUID DEFAULT NULL,
  p_seller_id UUID DEFAULT NULL,
  p_category_id UUID DEFAULT NULL,
  p_title TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_price NUMERIC DEFAULT NULL,
  p_city TEXT DEFAULT NULL,
  p_condition TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_is_promoted BOOLEAN DEFAULT NULL,
  p_promoted_until TIMESTAMPTZ DEFAULT NULL,
  p_rejection_reason TEXT DEFAULT NULL,
  p_clear_rejection BOOLEAN DEFAULT FALSE
)
RETURNS public.listings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_old public.listings;
  v_new public.listings;
BEGIN
  v_admin := public.require_admin('moderator');

  IF p_id IS NULL THEN
    IF p_seller_id IS NULL OR p_category_id IS NULL OR p_title IS NULL
       OR p_price IS NULL OR p_city IS NULL THEN
      RAISE EXCEPTION 'MISSING_FIELDS' USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO public.listings (
      seller_id, category_id, title, description, price, city,
      condition, status, is_promoted, promoted_until, boosted_at, rejection_reason
    ) VALUES (
      p_seller_id,
      p_category_id,
      trim(p_title),
      COALESCE(p_description, ''),
      p_price,
      trim(p_city),
      COALESCE(p_condition, 'used'),
      COALESCE(p_status, 'pending'),
      COALESCE(p_is_promoted, FALSE),
      p_promoted_until,
      CASE WHEN COALESCE(p_is_promoted, FALSE) THEN NOW() ELSE NULL END,
      CASE WHEN p_clear_rejection THEN NULL ELSE p_rejection_reason END
    )
    RETURNING * INTO v_new;

    PERFORM public.write_admin_audit(
      v_admin, 'create_listing', 'listing', v_new.id::TEXT, NULL, to_jsonb(v_new)
    );
    RETURN v_new;
  END IF;

  SELECT * INTO v_old FROM public.listings WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'LISTING_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF p_status IS NOT NULL AND p_status NOT IN (
    'pending', 'active', 'sold', 'archived', 'rejected'
  ) THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.listings SET
    seller_id = COALESCE(p_seller_id, seller_id),
    category_id = COALESCE(p_category_id, category_id),
    title = COALESCE(NULLIF(trim(p_title), ''), title),
    description = COALESCE(p_description, description),
    price = COALESCE(p_price, price),
    city = COALESCE(NULLIF(trim(p_city), ''), city),
    condition = COALESCE(p_condition, condition),
    status = COALESCE(p_status, status),
    is_promoted = COALESCE(p_is_promoted, is_promoted),
    promoted_until = CASE
      WHEN p_is_promoted IS FALSE THEN NULL
      ELSE COALESCE(p_promoted_until, promoted_until)
    END,
    boosted_at = CASE
      WHEN p_is_promoted IS FALSE THEN NULL
      WHEN p_is_promoted IS TRUE THEN COALESCE(boosted_at, NOW())
      ELSE boosted_at
    END,
    rejection_reason = CASE
      WHEN p_clear_rejection THEN NULL
      WHEN p_rejection_reason IS NOT NULL THEN p_rejection_reason
      ELSE rejection_reason
    END,
    updated_at = NOW()
  WHERE id = p_id
  RETURNING * INTO v_new;

  PERFORM public.write_admin_audit(
    v_admin, 'update_listing', 'listing', p_id::TEXT, to_jsonb(v_old), to_jsonb(v_new)
  );
  RETURN v_new;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_upsert_listing(
  UUID, UUID, UUID, TEXT, TEXT, NUMERIC, TEXT, TEXT, TEXT, BOOLEAN, TIMESTAMPTZ, TEXT, BOOLEAN
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_upsert_listing(
  UUID, UUID, UUID, TEXT, TEXT, NUMERIC, TEXT, TEXT, TEXT, BOOLEAN, TIMESTAMPTZ, TEXT, BOOLEAN
) TO authenticated;

COMMENT ON COLUMN public.listings.boosted_at IS
  'Set by admin boost; feed sorts promoted by boosted_at DESC';
