-- ============================================================
-- Fix: deleting a listing must not SET NULL listing_id on market
-- chats (violates conversations_type_fields_chk). Cascade instead.
-- ============================================================

DO $$
DECLARE
  v_con TEXT;
BEGIN
  SELECT con.conname INTO v_con
  FROM pg_constraint con
  JOIN pg_class rel ON rel.oid = con.conrelid
  JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
  WHERE nsp.nspname = 'public'
    AND rel.relname = 'conversations'
    AND con.contype = 'f'
    AND pg_get_constraintdef(con.oid) ILIKE '%listing_id%listings%';

  IF v_con IS NOT NULL THEN
    EXECUTE format(
      'ALTER TABLE public.conversations DROP CONSTRAINT %I',
      v_con
    );
  END IF;
END $$;

ALTER TABLE public.conversations
  ADD CONSTRAINT conversations_listing_id_fkey
  FOREIGN KEY (listing_id)
  REFERENCES public.listings (id)
  ON DELETE CASCADE;

-- Explicit cleanup in admin delete (safe if CASCADE already removed rows).
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

  DELETE FROM public.conversations
  WHERE type = 'market' AND listing_id = p_id;

  DELETE FROM public.listings WHERE id = p_id;

  PERFORM public.write_admin_audit(
    v_admin, 'delete_listing', 'listing', p_id::TEXT, to_jsonb(v_old), NULL
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_listing(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_listing(UUID) TO authenticated;
