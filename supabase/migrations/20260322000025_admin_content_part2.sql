-- ============================================================
-- Admin Stage 2 part 2: clans, ranking, market, categories,
-- achievements, cities RPCs
-- ============================================================

-- ===================== CLANS =====================

CREATE OR REPLACE FUNCTION public.admin_list_clans(
  p_search TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  name TEXT,
  tag TEXT,
  avatar_url TEXT,
  description TEXT,
  leader_id UUID,
  leader_nickname TEXT,
  members_count BIGINT,
  rating INTEGER,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_q TEXT := NULLIF(lower(trim(COALESCE(p_search, ''))), '');
  v_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
  v_offset INTEGER := GREATEST(COALESCE(p_offset, 0), 0);
BEGIN
  PERFORM public.require_admin('moderator');

  RETURN QUERY
  SELECT
    c.id,
    c.name,
    c.tag,
    c.avatar_url,
    c.description,
    c.leader_id,
    lp.nickname,
    (SELECT COUNT(*) FROM public.clan_members cm WHERE cm.clan_id = c.id),
    c.rating,
    c.created_at
  FROM public.clans c
  LEFT JOIN public.profiles lp ON lp.id = c.leader_id
  WHERE (
    v_q IS NULL
    OR lower(c.name) LIKE '%' || v_q || '%'
    OR lower(c.tag) LIKE '%' || v_q || '%'
  )
  ORDER BY c.rating DESC, c.name ASC
  LIMIT v_limit OFFSET v_offset;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_clans(TEXT, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_clans(TEXT, INTEGER, INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_upsert_clan(
  p_id UUID DEFAULT NULL,
  p_name TEXT DEFAULT NULL,
  p_tag TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_avatar_url TEXT DEFAULT NULL,
  p_clear_avatar BOOLEAN DEFAULT FALSE,
  p_leader_id UUID DEFAULT NULL
)
RETURNS public.clans
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_old public.clans;
  v_new public.clans;
  v_tag TEXT;
BEGIN
  v_admin := public.require_admin('moderator');

  IF p_id IS NULL THEN
    IF p_name IS NULL OR p_tag IS NULL OR p_leader_id IS NULL THEN
      RAISE EXCEPTION 'MISSING_FIELDS' USING ERRCODE = 'P0001';
    END IF;
    v_tag := upper(trim(p_tag));

    INSERT INTO public.clans (name, tag, description, avatar_url, leader_id)
    VALUES (
      trim(p_name),
      v_tag,
      COALESCE(p_description, ''),
      CASE WHEN p_clear_avatar THEN NULL ELSE p_avatar_url END,
      p_leader_id
    )
    RETURNING * INTO v_new;

    -- one clan per user
    DELETE FROM public.clan_members WHERE user_id = p_leader_id;

    INSERT INTO public.clan_members (clan_id, user_id, role)
    VALUES (v_new.id, p_leader_id, 'leader');

    PERFORM public.recompute_clan_rating(v_new.id);

    SELECT * INTO v_new FROM public.clans WHERE id = v_new.id;

    PERFORM public.write_admin_audit(
      v_admin, 'create_clan', 'clan', v_new.id::TEXT, NULL, to_jsonb(v_new)
    );
    RETURN v_new;
  END IF;

  SELECT * INTO v_old FROM public.clans WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CLAN_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.clans SET
    name = COALESCE(NULLIF(trim(p_name), ''), name),
    tag = COALESCE(NULLIF(upper(trim(p_tag)), ''), tag),
    description = COALESCE(p_description, description),
    avatar_url = CASE
      WHEN p_clear_avatar THEN NULL
      WHEN p_avatar_url IS NOT NULL THEN p_avatar_url
      ELSE avatar_url
    END,
    leader_id = COALESCE(p_leader_id, leader_id)
  WHERE id = p_id
  RETURNING * INTO v_new;

  IF p_leader_id IS NOT NULL AND p_leader_id IS DISTINCT FROM v_old.leader_id THEN
    INSERT INTO public.clan_members (clan_id, user_id, role)
    VALUES (p_id, p_leader_id, 'leader')
    ON CONFLICT (clan_id, user_id) DO UPDATE SET role = 'leader';

    UPDATE public.clan_members
    SET role = 'member'
    WHERE clan_id = p_id AND user_id = v_old.leader_id AND user_id <> p_leader_id;

    DELETE FROM public.clan_members
    WHERE user_id = p_leader_id AND clan_id <> p_id;

    PERFORM public.recompute_clan_rating(p_id);
    SELECT * INTO v_new FROM public.clans WHERE id = p_id;
  END IF;

  PERFORM public.write_admin_audit(
    v_admin, 'update_clan', 'clan', p_id::TEXT, to_jsonb(v_old), to_jsonb(v_new)
  );
  RETURN v_new;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_upsert_clan(
  UUID, TEXT, TEXT, TEXT, TEXT, BOOLEAN, UUID
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_upsert_clan(
  UUID, TEXT, TEXT, TEXT, TEXT, BOOLEAN, UUID
) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_delete_clan(p_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_old public.clans;
BEGIN
  v_admin := public.require_admin('admin');
  SELECT * INTO v_old FROM public.clans WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CLAN_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;
  DELETE FROM public.clans WHERE id = p_id;
  PERFORM public.write_admin_audit(
    v_admin, 'delete_clan', 'clan', p_id::TEXT, to_jsonb(v_old), NULL
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_clan(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_clan(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_list_clan_members(p_clan_id UUID)
RETURNS TABLE (
  user_id UUID,
  nickname TEXT,
  avatar_url TEXT,
  city TEXT,
  rating INTEGER,
  role TEXT,
  joined_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.require_admin('moderator');
  RETURN QUERY
  SELECT
    cm.user_id,
    p.nickname,
    p.avatar_url,
    p.city,
    p.rating,
    cm.role,
    cm.joined_at
  FROM public.clan_members cm
  JOIN public.profiles p ON p.id = cm.user_id
  WHERE cm.clan_id = p_clan_id
  ORDER BY
    CASE cm.role WHEN 'leader' THEN 0 WHEN 'officer' THEN 1 ELSE 2 END,
    p.nickname;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_clan_members(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_clan_members(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_add_clan_member(
  p_clan_id UUID,
  p_user_id UUID,
  p_role TEXT DEFAULT 'member'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_role TEXT := COALESCE(NULLIF(p_role, ''), 'member');
BEGIN
  v_admin := public.require_admin('moderator');
  IF v_role NOT IN ('leader', 'officer', 'member') THEN
    RAISE EXCEPTION 'INVALID_ROLE' USING ERRCODE = 'P0001';
  END IF;

  DELETE FROM public.clan_members WHERE user_id = p_user_id AND clan_id <> p_clan_id;

  INSERT INTO public.clan_members (clan_id, user_id, role)
  VALUES (p_clan_id, p_user_id, v_role)
  ON CONFLICT (clan_id, user_id) DO UPDATE SET role = EXCLUDED.role;

  IF v_role = 'leader' THEN
    UPDATE public.clans SET leader_id = p_user_id WHERE id = p_clan_id;
    UPDATE public.clan_members
    SET role = 'member'
    WHERE clan_id = p_clan_id AND user_id <> p_user_id AND role = 'leader';
  END IF;

  PERFORM public.recompute_clan_rating(p_clan_id);
  PERFORM public.write_admin_audit(
    v_admin, 'add_clan_member', 'clan', p_clan_id::TEXT,
    NULL, jsonb_build_object('user_id', p_user_id, 'role', v_role)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_add_clan_member(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_add_clan_member(UUID, UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_remove_clan_member(
  p_clan_id UUID,
  p_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_clan public.clans;
BEGIN
  v_admin := public.require_admin('moderator');
  SELECT * INTO v_clan FROM public.clans WHERE id = p_clan_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CLAN_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  DELETE FROM public.clan_members
  WHERE clan_id = p_clan_id AND user_id = p_user_id;

  IF v_clan.leader_id = p_user_id THEN
    UPDATE public.clans SET leader_id = NULL WHERE id = p_clan_id;
  END IF;

  PERFORM public.recompute_clan_rating(p_clan_id);
  PERFORM public.write_admin_audit(
    v_admin, 'remove_clan_member', 'clan', p_clan_id::TEXT,
    jsonb_build_object('user_id', p_user_id), NULL
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_remove_clan_member(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_remove_clan_member(UUID, UUID) TO authenticated;

-- Ranking (admin can set player rating; clan rating is never set manually)
CREATE OR REPLACE FUNCTION public.admin_set_player_rating(
  p_user_id UUID,
  p_rating INTEGER
)
RETURNS public.profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_rating IS NULL OR p_rating < 0 THEN
    RAISE EXCEPTION 'INVALID_RATING' USING ERRCODE = 'P0001';
  END IF;
  RETURN public.admin_update_profile(
    p_user_id := p_user_id,
    p_rating := p_rating
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_player_rating(UUID, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_player_rating(UUID, INTEGER) TO authenticated;

-- ===================== MARKET =====================

CREATE OR REPLACE FUNCTION public.admin_list_listings(
  p_category_id UUID DEFAULT NULL,
  p_city TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_seller_id UUID DEFAULT NULL,
  p_date_from TIMESTAMPTZ DEFAULT NULL,
  p_date_to TIMESTAMPTZ DEFAULT NULL,
  p_price_min NUMERIC DEFAULT NULL,
  p_price_max NUMERIC DEFAULT NULL,
  p_search TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  title TEXT,
  price NUMERIC,
  city TEXT,
  status TEXT,
  views_count INTEGER,
  is_promoted BOOLEAN,
  promoted_until TIMESTAMPTZ,
  created_at TIMESTAMPTZ,
  seller_id UUID,
  seller_nickname TEXT,
  category_id UUID,
  category_name TEXT,
  cover_url TEXT,
  rejection_reason TEXT,
  condition TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_q TEXT := NULLIF(lower(trim(COALESCE(p_search, ''))), '');
  v_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
  v_offset INTEGER := GREATEST(COALESCE(p_offset, 0), 0);
BEGIN
  PERFORM public.require_admin('moderator');

  RETURN QUERY
  SELECT
    l.id,
    l.title,
    l.price,
    l.city,
    l.status,
    l.views_count,
    l.is_promoted,
    l.promoted_until,
    l.created_at,
    l.seller_id,
    s.nickname,
    l.category_id,
    c.name,
    (
      SELECT li.url FROM public.listing_images li
      WHERE li.listing_id = l.id
      ORDER BY li.sort_order ASC
      LIMIT 1
    ),
    l.rejection_reason,
    l.condition
  FROM public.listings l
  JOIN public.profiles s ON s.id = l.seller_id
  JOIN public.categories c ON c.id = l.category_id
  WHERE (p_category_id IS NULL OR l.category_id = p_category_id
         OR c.parent_id = p_category_id)
    AND (p_city IS NULL OR l.city = p_city)
    AND (p_status IS NULL OR l.status = p_status)
    AND (p_seller_id IS NULL OR l.seller_id = p_seller_id)
    AND (p_date_from IS NULL OR l.created_at >= p_date_from)
    AND (p_date_to IS NULL OR l.created_at <= p_date_to)
    AND (p_price_min IS NULL OR l.price >= p_price_min)
    AND (p_price_max IS NULL OR l.price <= p_price_max)
    AND (v_q IS NULL OR lower(l.title) LIKE '%' || v_q || '%')
  ORDER BY l.created_at DESC
  LIMIT v_limit OFFSET v_offset;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_listings(
  UUID, TEXT, TEXT, UUID, TIMESTAMPTZ, TIMESTAMPTZ, NUMERIC, NUMERIC, TEXT, INTEGER, INTEGER
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_listings(
  UUID, TEXT, TEXT, UUID, TIMESTAMPTZ, TIMESTAMPTZ, NUMERIC, NUMERIC, TEXT, INTEGER, INTEGER
) TO authenticated;

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
      condition, status, is_promoted, promoted_until, rejection_reason
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
    rejection_reason = CASE
      WHEN p_clear_rejection THEN NULL
      WHEN p_rejection_reason IS NOT NULL THEN p_rejection_reason
      ELSE rejection_reason
    END
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

CREATE OR REPLACE FUNCTION public.admin_delete_listing(p_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_old public.listings;
BEGIN
  v_admin := public.require_admin('admin');
  SELECT * INTO v_old FROM public.listings WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'LISTING_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;
  DELETE FROM public.listings WHERE id = p_id;
  PERFORM public.write_admin_audit(
    v_admin, 'delete_listing', 'listing', p_id::TEXT, to_jsonb(v_old), NULL
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_listing(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_listing(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_listing_images(
  p_listing_id UUID,
  p_urls TEXT[]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  i INTEGER;
BEGIN
  v_admin := public.require_admin('moderator');
  IF NOT EXISTS (SELECT 1 FROM public.listings WHERE id = p_listing_id) THEN
    RAISE EXCEPTION 'LISTING_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  DELETE FROM public.listing_images WHERE listing_id = p_listing_id;

  IF p_urls IS NOT NULL THEN
    FOR i IN 1 .. COALESCE(array_length(p_urls, 1), 0) LOOP
      INSERT INTO public.listing_images (listing_id, url, sort_order)
      VALUES (p_listing_id, p_urls[i], i - 1);
    END LOOP;
  END IF;

  PERFORM public.write_admin_audit(
    v_admin, 'set_listing_images', 'listing', p_listing_id::TEXT,
    NULL, jsonb_build_object('urls', to_jsonb(p_urls))
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_listing_images(UUID, TEXT[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_listing_images(UUID, TEXT[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_moderate_listing(
  p_id UUID,
  p_action TEXT,
  p_reason TEXT DEFAULT NULL
)
RETURNS public.listings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT;
  v_clear BOOLEAN := FALSE;
  v_reason TEXT := p_reason;
BEGIN
  PERFORM public.require_admin('moderator');

  IF p_action = 'approve' THEN
    v_status := 'active';
    v_clear := TRUE;
    v_reason := NULL;
  ELSIF p_action = 'reject' THEN
    v_status := 'rejected';
    IF NULLIF(trim(COALESCE(p_reason, '')), '') IS NULL THEN
      RAISE EXCEPTION 'REASON_REQUIRED' USING ERRCODE = 'P0001';
    END IF;
  ELSIF p_action = 'archive' THEN
    v_status := 'archived';
  ELSIF p_action = 'restore' THEN
    v_status := 'pending';
    v_clear := TRUE;
  ELSE
    RAISE EXCEPTION 'INVALID_ACTION' USING ERRCODE = 'P0001';
  END IF;

  RETURN public.admin_upsert_listing(
    p_id := p_id,
    p_status := v_status,
    p_rejection_reason := v_reason,
    p_clear_rejection := v_clear
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_moderate_listing(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_moderate_listing(UUID, TEXT, TEXT) TO authenticated;

-- ===================== CATEGORIES =====================

CREATE OR REPLACE FUNCTION public.admin_list_categories()
RETURNS SETOF public.categories
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.require_admin('moderator');
  RETURN QUERY
  SELECT * FROM public.categories
  ORDER BY sort_order ASC, name ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_categories() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_categories() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_upsert_category(
  p_id UUID DEFAULT NULL,
  p_name TEXT DEFAULT NULL,
  p_icon TEXT DEFAULT NULL,
  p_sort_order INTEGER DEFAULT NULL,
  p_parent_id UUID DEFAULT NULL,
  p_clear_parent BOOLEAN DEFAULT FALSE
)
RETURNS public.categories
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_old public.categories;
  v_new public.categories;
BEGIN
  v_admin := public.require_admin('moderator');

  IF p_id IS NULL THEN
    IF p_name IS NULL THEN
      RAISE EXCEPTION 'MISSING_FIELDS' USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO public.categories (name, icon, sort_order, parent_id)
    VALUES (
      trim(p_name),
      p_icon,
      COALESCE(p_sort_order, 0),
      CASE WHEN p_clear_parent THEN NULL ELSE p_parent_id END
    )
    RETURNING * INTO v_new;
    PERFORM public.write_admin_audit(
      v_admin, 'create_category', 'category', v_new.id::TEXT, NULL, to_jsonb(v_new)
    );
    RETURN v_new;
  END IF;

  SELECT * INTO v_old FROM public.categories WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CATEGORY_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.categories SET
    name = COALESCE(NULLIF(trim(p_name), ''), name),
    icon = COALESCE(p_icon, icon),
    sort_order = COALESCE(p_sort_order, sort_order),
    parent_id = CASE
      WHEN p_clear_parent THEN NULL
      WHEN p_parent_id IS NOT NULL THEN p_parent_id
      ELSE parent_id
    END
  WHERE id = p_id
  RETURNING * INTO v_new;

  PERFORM public.write_admin_audit(
    v_admin, 'update_category', 'category', p_id::TEXT, to_jsonb(v_old), to_jsonb(v_new)
  );
  RETURN v_new;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_upsert_category(
  UUID, TEXT, TEXT, INTEGER, UUID, BOOLEAN
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_upsert_category(
  UUID, TEXT, TEXT, INTEGER, UUID, BOOLEAN
) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_delete_category(p_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_old public.categories;
BEGIN
  v_admin := public.require_admin('admin');
  SELECT * INTO v_old FROM public.categories WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CATEGORY_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;
  DELETE FROM public.categories WHERE id = p_id;
  PERFORM public.write_admin_audit(
    v_admin, 'delete_category', 'category', p_id::TEXT, to_jsonb(v_old), NULL
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_category(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_category(UUID) TO authenticated;

-- ===================== ACHIEVEMENTS =====================

CREATE OR REPLACE FUNCTION public.admin_list_achievements()
RETURNS SETOF public.achievements
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.require_admin('moderator');
  RETURN QUERY
  SELECT * FROM public.achievements
  ORDER BY type ASC, required_value ASC, title ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_achievements() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_achievements() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_upsert_achievement(
  p_id UUID DEFAULT NULL,
  p_title TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_icon TEXT DEFAULT NULL,
  p_type TEXT DEFAULT NULL,
  p_required_value INTEGER DEFAULT NULL,
  p_is_active BOOLEAN DEFAULT NULL
)
RETURNS public.achievements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_old public.achievements;
  v_new public.achievements;
BEGIN
  v_admin := public.require_admin('moderator');

  IF p_type IS NOT NULL AND p_type NOT IN (
    'games_played', 'wins', 'polygons_visited', 'rating', 'events_count'
  ) THEN
    RAISE EXCEPTION 'INVALID_TYPE' USING ERRCODE = 'P0001';
  END IF;

  IF p_id IS NULL THEN
    IF p_title IS NULL OR p_type IS NULL OR p_required_value IS NULL THEN
      RAISE EXCEPTION 'MISSING_FIELDS' USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO public.achievements (
      title, description, icon, type, required_value, is_active
    ) VALUES (
      trim(p_title),
      COALESCE(p_description, ''),
      COALESCE(p_icon, 'award'),
      p_type,
      p_required_value,
      COALESCE(p_is_active, TRUE)
    )
    RETURNING * INTO v_new;
    PERFORM public.write_admin_audit(
      v_admin, 'create_achievement', 'achievement', v_new.id::TEXT, NULL, to_jsonb(v_new)
    );
    RETURN v_new;
  END IF;

  SELECT * INTO v_old FROM public.achievements WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ACHIEVEMENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.achievements SET
    title = COALESCE(NULLIF(trim(p_title), ''), title),
    description = COALESCE(p_description, description),
    icon = COALESCE(p_icon, icon),
    type = COALESCE(p_type, type),
    required_value = COALESCE(p_required_value, required_value),
    is_active = COALESCE(p_is_active, is_active)
  WHERE id = p_id
  RETURNING * INTO v_new;

  PERFORM public.write_admin_audit(
    v_admin, 'update_achievement', 'achievement', p_id::TEXT, to_jsonb(v_old), to_jsonb(v_new)
  );
  RETURN v_new;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_upsert_achievement(
  UUID, TEXT, TEXT, TEXT, TEXT, INTEGER, BOOLEAN
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_upsert_achievement(
  UUID, TEXT, TEXT, TEXT, TEXT, INTEGER, BOOLEAN
) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_delete_achievement(p_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_old public.achievements;
BEGIN
  v_admin := public.require_admin('admin');
  SELECT * INTO v_old FROM public.achievements WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ACHIEVEMENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;
  DELETE FROM public.achievements WHERE id = p_id;
  PERFORM public.write_admin_audit(
    v_admin, 'delete_achievement', 'achievement', p_id::TEXT, to_jsonb(v_old), NULL
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_achievement(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_achievement(UUID) TO authenticated;

-- ===================== CITIES =====================

CREATE OR REPLACE FUNCTION public.admin_list_cities(p_all BOOLEAN DEFAULT TRUE)
RETURNS SETOF public.app_cities
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.require_admin('moderator');
  RETURN QUERY
  SELECT * FROM public.app_cities
  WHERE p_all OR is_active
  ORDER BY sort_order ASC, name ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_cities(BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_cities(BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.list_active_cities()
RETURNS TABLE (id UUID, name TEXT, sort_order INTEGER)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id, name, sort_order
  FROM public.app_cities
  WHERE is_active = TRUE
  ORDER BY sort_order ASC, name ASC;
$$;

REVOKE ALL ON FUNCTION public.list_active_cities() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_active_cities() TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_upsert_city(
  p_id UUID DEFAULT NULL,
  p_name TEXT DEFAULT NULL,
  p_sort_order INTEGER DEFAULT NULL,
  p_is_active BOOLEAN DEFAULT NULL
)
RETURNS public.app_cities
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_old public.app_cities;
  v_new public.app_cities;
BEGIN
  v_admin := public.require_admin('admin');

  IF p_id IS NULL THEN
    IF p_name IS NULL THEN
      RAISE EXCEPTION 'MISSING_FIELDS' USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO public.app_cities (name, sort_order, is_active)
    VALUES (trim(p_name), COALESCE(p_sort_order, 0), COALESCE(p_is_active, TRUE))
    RETURNING * INTO v_new;
    PERFORM public.write_admin_audit(
      v_admin, 'create_city', 'city', v_new.id::TEXT, NULL, to_jsonb(v_new)
    );
    RETURN v_new;
  END IF;

  SELECT * INTO v_old FROM public.app_cities WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CITY_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.app_cities SET
    name = COALESCE(NULLIF(trim(p_name), ''), name),
    sort_order = COALESCE(p_sort_order, sort_order),
    is_active = COALESCE(p_is_active, is_active)
  WHERE id = p_id
  RETURNING * INTO v_new;

  PERFORM public.write_admin_audit(
    v_admin, 'update_city', 'city', p_id::TEXT, to_jsonb(v_old), to_jsonb(v_new)
  );
  RETURN v_new;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_upsert_city(UUID, TEXT, INTEGER, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_upsert_city(UUID, TEXT, INTEGER, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_delete_city(p_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_old public.app_cities;
BEGIN
  v_admin := public.require_admin('admin');
  SELECT * INTO v_old FROM public.app_cities WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CITY_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;
  DELETE FROM public.app_cities WHERE id = p_id;
  PERFORM public.write_admin_audit(
    v_admin, 'delete_city', 'city', p_id::TEXT, to_jsonb(v_old), NULL
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_city(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_city(UUID) TO authenticated;

-- Admins may read all listings/categories for joins
DROP POLICY IF EXISTS "Admins read all listings" ON public.listings;
CREATE POLICY "Admins read all listings"
  ON public.listings FOR SELECT TO authenticated
  USING (public.is_admin());

DROP POLICY IF EXISTS "Admins read listing images" ON public.listing_images;
CREATE POLICY "Admins read listing images"
  ON public.listing_images FOR SELECT TO authenticated
  USING (public.is_admin());

COMMENT ON TABLE public.app_cities IS 'Reference cities for app + admin dictionaries';
COMMENT ON COLUMN public.clans.rating IS 'Computed SUM(member profiles.rating) — never set manually by admin';
