-- ============================================================
-- City chats: one conversation per city; auto-join by profiles.city
-- ============================================================

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS city_name TEXT;

-- Expand type check
ALTER TABLE public.conversations DROP CONSTRAINT IF EXISTS conversations_type_check;
ALTER TABLE public.conversations
  ADD CONSTRAINT conversations_type_check
  CHECK (type IN ('market', 'clan', 'user', 'city'));

-- Market / clan / city field integrity
ALTER TABLE public.conversations DROP CONSTRAINT IF EXISTS conversations_market_listing_chk;
ALTER TABLE public.conversations DROP CONSTRAINT IF EXISTS conversations_check;
-- Original anonymous checks may be named conversations_check / conversations_check1
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT con.conname
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
    WHERE nsp.nspname = 'public'
      AND rel.relname = 'conversations'
      AND con.contype = 'c'
      AND pg_get_constraintdef(con.oid) ILIKE '%listing_id%'
  LOOP
    EXECUTE format('ALTER TABLE public.conversations DROP CONSTRAINT IF EXISTS %I', r.conname);
  END LOOP;

  FOR r IN
    SELECT con.conname
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
    WHERE nsp.nspname = 'public'
      AND rel.relname = 'conversations'
      AND con.contype = 'c'
      AND pg_get_constraintdef(con.oid) ILIKE '%clan_id%'
      AND pg_get_constraintdef(con.oid) NOT ILIKE '%clan_channel%'
  LOOP
    EXECUTE format('ALTER TABLE public.conversations DROP CONSTRAINT IF EXISTS %I', r.conname);
  END LOOP;
END;
$$;

ALTER TABLE public.conversations DROP CONSTRAINT IF EXISTS conversations_type_fields_chk;
ALTER TABLE public.conversations
  ADD CONSTRAINT conversations_type_fields_chk
  CHECK (
    (
      type = 'market'
      AND listing_id IS NOT NULL
      AND clan_id IS NULL
      AND city_name IS NULL
    )
    OR (
      type = 'clan'
      AND clan_id IS NOT NULL
      AND listing_id IS NULL
      AND city_name IS NULL
    )
    OR (
      type = 'user'
      AND listing_id IS NULL
      AND clan_id IS NULL
      AND city_name IS NULL
    )
    OR (
      type = 'city'
      AND city_name IS NOT NULL
      AND listing_id IS NULL
      AND clan_id IS NULL
      AND clan_channel IS NULL
    )
  );

-- clan_channel constraint still requires non-clan ⇒ channel NULL (covers city)
ALTER TABLE public.conversations
  DROP CONSTRAINT IF EXISTS conversations_clan_channel_chk;

ALTER TABLE public.conversations
  ADD CONSTRAINT conversations_clan_channel_chk
  CHECK (
    (type <> 'clan' AND clan_channel IS NULL)
    OR (type = 'clan' AND clan_channel IN ('general', 'officers'))
  );

CREATE UNIQUE INDEX IF NOT EXISTS conversations_city_unique_idx
  ON public.conversations (lower(city_name))
  WHERE type = 'city' AND city_name IS NOT NULL;

CREATE OR REPLACE FUNCTION public.ensure_city_chat(p_city TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_city TEXT := NULLIF(trim(p_city), '');
  v_conv UUID;
BEGIN
  IF v_city IS NULL THEN
    RAISE EXCEPTION 'INVALID_CITY' USING ERRCODE = 'P0001';
  END IF;

  SELECT id INTO v_conv
  FROM public.conversations
  WHERE type = 'city'
    AND lower(city_name) = lower(v_city)
  LIMIT 1;

  IF v_conv IS NULL THEN
    BEGIN
      INSERT INTO public.conversations (type, title, city_name)
      VALUES ('city', v_city, v_city)
      RETURNING id INTO v_conv;
    EXCEPTION
      WHEN unique_violation THEN
        SELECT id INTO v_conv
        FROM public.conversations
        WHERE type = 'city'
          AND lower(city_name) = lower(v_city)
        LIMIT 1;
    END;
  ELSE
    UPDATE public.conversations
    SET title = v_city,
        city_name = v_city
    WHERE id = v_conv
      AND (title IS DISTINCT FROM v_city OR city_name IS DISTINCT FROM v_city);
  END IF;

  RETURN v_conv;
END;
$$;

CREATE OR REPLACE FUNCTION public.join_city_chat(p_user_id UUID, p_city TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_conv UUID;
BEGIN
  v_conv := public.ensure_city_chat(p_city);

  INSERT INTO public.conversation_members (conversation_id, user_id, role)
  VALUES (v_conv, p_user_id, 'member')
  ON CONFLICT DO NOTHING;

  RETURN v_conv;
END;
$$;

CREATE OR REPLACE FUNCTION public.open_city_chat()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_city TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT city INTO v_city FROM public.profiles WHERE id = v_uid;
  IF v_city IS NULL OR trim(v_city) = '' THEN
    RAISE EXCEPTION 'CITY_REQUIRED' USING ERRCODE = 'P0001';
  END IF;

  RETURN public.join_city_chat(v_uid, v_city);
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_profiles_sync_city_chat()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.city IS NOT NULL AND trim(NEW.city) <> '' THEN
      PERFORM public.join_city_chat(NEW.id, NEW.city);
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.city IS DISTINCT FROM OLD.city THEN
    DELETE FROM public.conversation_members cm
    USING public.conversations c
    WHERE cm.conversation_id = c.id
      AND cm.user_id = NEW.id
      AND c.type = 'city';

    IF NEW.city IS NOT NULL AND trim(NEW.city) <> '' THEN
      PERFORM public.join_city_chat(NEW.id, NEW.city);
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_sync_city_chat_aiud ON public.profiles;
CREATE TRIGGER profiles_sync_city_chat_aiud
  AFTER INSERT OR UPDATE OF city ON public.profiles
  FOR EACH ROW
  EXECUTE PROCEDURE public.trg_profiles_sync_city_chat();

REVOKE ALL ON FUNCTION public.ensure_city_chat(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_city_chat(TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.join_city_chat(UUID, TEXT) FROM PUBLIC;
-- internal; keep callable by authenticated for safety via open_city_chat only ideally
-- but SECURITY DEFINER join used by trigger — revoke from authenticated
REVOKE ALL ON FUNCTION public.join_city_chat(UUID, TEXT) FROM authenticated;

REVOKE ALL ON FUNCTION public.open_city_chat() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.open_city_chat() TO authenticated;

-- Backfill: create chats and memberships for existing profiles
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT DISTINCT trim(city) AS city
    FROM public.profiles
    WHERE city IS NOT NULL AND trim(city) <> ''
  LOOP
    PERFORM public.ensure_city_chat(r.city);
  END LOOP;

  FOR r IN
    SELECT id, city
    FROM public.profiles
    WHERE city IS NOT NULL AND trim(city) <> ''
  LOOP
    PERFORM public.join_city_chat(r.id, r.city);
  END LOOP;
END;
$$;

COMMENT ON COLUMN public.conversations.city_name IS
  'City chat key; matches profiles.city (case-insensitive unique)';
COMMENT ON FUNCTION public.open_city_chat() IS
  'Ensure current user is in their city chat; create chat if needed';
