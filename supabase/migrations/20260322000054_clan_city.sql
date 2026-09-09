-- ============================================================
-- Clan location (city)
-- ============================================================

ALTER TABLE public.clans
  ADD COLUMN IF NOT EXISTS city TEXT;

CREATE INDEX IF NOT EXISTS clans_city_lower_idx
  ON public.clans (lower(city))
  WHERE city IS NOT NULL AND trim(city) <> '';

-- ---------- create_clan: require city ----------
DROP FUNCTION IF EXISTS public.create_clan(TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.create_clan(TEXT, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.create_clan(
  p_name TEXT,
  p_tag TEXT,
  p_description TEXT DEFAULT '',
  p_avatar_url TEXT DEFAULT NULL,
  p_city TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_name TEXT := trim(p_name);
  v_tag TEXT := UPPER(trim(p_tag));
  v_desc TEXT := COALESCE(trim(p_description), '');
  v_city TEXT := NULLIF(trim(p_city), '');
  v_clan UUID;
  v_conv UUID;
  v_level INTEGER;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  v_level := public.player_level(v_uid);
  IF v_level < 3 THEN
    RAISE EXCEPTION 'LEVEL_TOO_LOW' USING ERRCODE = 'P0001';
  END IF;

  IF v_name IS NULL OR char_length(v_name) < 2 OR char_length(v_name) > 40 THEN
    RAISE EXCEPTION 'INVALID_NAME' USING ERRCODE = 'P0001';
  END IF;

  IF v_tag IS NULL OR char_length(v_tag) < 2 OR char_length(v_tag) > 6 THEN
    RAISE EXCEPTION 'INVALID_TAG' USING ERRCODE = 'P0001';
  END IF;

  IF v_tag !~ '^[A-Z0-9А-ЯЁ]+$' THEN
    RAISE EXCEPTION 'INVALID_TAG' USING ERRCODE = 'P0001';
  END IF;

  IF v_city IS NULL OR char_length(v_city) < 2 OR char_length(v_city) > 80 THEN
    RAISE EXCEPTION 'INVALID_CITY' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (SELECT 1 FROM public.clan_members WHERE user_id = v_uid) THEN
    RAISE EXCEPTION 'ALREADY_IN_CLAN' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (SELECT 1 FROM public.clans WHERE LOWER(name) = LOWER(v_name)) THEN
    RAISE EXCEPTION 'NAME_TAKEN' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (SELECT 1 FROM public.clans WHERE UPPER(tag) = v_tag) THEN
    RAISE EXCEPTION 'TAG_TAKEN' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.clans (name, tag, description, avatar_url, leader_id, city)
  VALUES (v_name, v_tag, v_desc, p_avatar_url, v_uid, v_city)
  RETURNING id INTO v_clan;

  INSERT INTO public.clan_members (clan_id, user_id, role)
  VALUES (v_clan, v_uid, 'leader');

  SELECT id INTO v_conv
  FROM public.conversations
  WHERE type = 'clan' AND clan_id = v_clan AND clan_channel = 'general';

  IF v_conv IS NULL THEN
    INSERT INTO public.conversations (type, title, clan_id, clan_channel)
    VALUES ('clan', v_name, v_clan, 'general');
  END IF;

  PERFORM public.recompute_clan_rating(v_clan);
  RETURN v_clan;
END;
$$;

REVOKE ALL ON FUNCTION public.create_clan(TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_clan(TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

COMMENT ON FUNCTION public.create_clan(TEXT, TEXT, TEXT, TEXT, TEXT) IS
  'Create clan — requires player level >= 3 and city (местоположение)';

-- Leader can update clan city / description
CREATE OR REPLACE FUNCTION public.update_clan_info(
  p_clan_id UUID,
  p_city TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL
)
RETURNS public.clans
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_city TEXT := NULLIF(trim(p_city), '');
  v_row public.clans;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_row FROM public.clans WHERE id = p_clan_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CLAN_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_row.leader_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'NOT_CLAN_LEADER' USING ERRCODE = '42501';
  END IF;

  IF p_city IS NOT NULL THEN
    IF v_city IS NULL OR char_length(v_city) < 2 OR char_length(v_city) > 80 THEN
      RAISE EXCEPTION 'INVALID_CITY' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  UPDATE public.clans SET
    city = CASE WHEN p_city IS NOT NULL THEN v_city ELSE city END,
    description = CASE
      WHEN p_description IS NOT NULL THEN COALESCE(trim(p_description), '')
      ELSE description
    END
  WHERE id = p_clan_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.update_clan_info(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_clan_info(UUID, TEXT, TEXT) TO authenticated;

-- ---------- Admin list / upsert ----------
DROP FUNCTION IF EXISTS public.admin_list_clans(TEXT, INTEGER, INTEGER);

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
  city TEXT,
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
    c.city,
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
    OR lower(COALESCE(c.city, '')) LIKE '%' || v_q || '%'
  )
  ORDER BY c.rating DESC, c.name ASC
  LIMIT v_limit OFFSET v_offset;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_clans(TEXT, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_clans(TEXT, INTEGER, INTEGER) TO authenticated;

DROP FUNCTION IF EXISTS public.admin_upsert_clan(
  UUID, TEXT, TEXT, TEXT, TEXT, BOOLEAN, UUID
);
DROP FUNCTION IF EXISTS public.admin_upsert_clan(
  UUID, TEXT, TEXT, TEXT, TEXT, BOOLEAN, UUID, TEXT
);

CREATE OR REPLACE FUNCTION public.admin_upsert_clan(
  p_id UUID DEFAULT NULL,
  p_name TEXT DEFAULT NULL,
  p_tag TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_avatar_url TEXT DEFAULT NULL,
  p_clear_avatar BOOLEAN DEFAULT FALSE,
  p_leader_id UUID DEFAULT NULL,
  p_city TEXT DEFAULT NULL
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
  v_city TEXT := NULLIF(trim(p_city), '');
BEGIN
  v_admin := public.require_admin('moderator');

  IF p_id IS NULL THEN
    IF p_name IS NULL OR p_tag IS NULL OR p_leader_id IS NULL THEN
      RAISE EXCEPTION 'MISSING_FIELDS' USING ERRCODE = 'P0001';
    END IF;
    v_tag := upper(trim(p_tag));

    INSERT INTO public.clans (name, tag, description, avatar_url, leader_id, city)
    VALUES (
      trim(p_name),
      v_tag,
      COALESCE(p_description, ''),
      CASE WHEN p_clear_avatar THEN NULL ELSE p_avatar_url END,
      p_leader_id,
      v_city
    )
    RETURNING * INTO v_new;

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
    city = CASE
      WHEN p_city IS NULL THEN city
      ELSE v_city
    END,
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

REVOKE ALL ON FUNCTION public.admin_upsert_clan(UUID, TEXT, TEXT, TEXT, TEXT, BOOLEAN, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_upsert_clan(UUID, TEXT, TEXT, TEXT, TEXT, BOOLEAN, UUID, TEXT) TO authenticated;
