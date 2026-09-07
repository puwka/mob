-- ============================================================
-- Fix: registered users must NOT auto-join a clan.
-- Remove seed clan + memberships; join only via requests.
-- ============================================================

-- Remove seed memberships first (triggers sync chat)
DELETE FROM public.clan_members
WHERE clan_id = 'c1000000-0000-4000-8000-000000000001';

-- Remove seed clan conversation (cascade members/messages as configured)
DELETE FROM public.conversations
WHERE clan_id = 'c1000000-0000-4000-8000-000000000001'
   OR id = 'c2000000-0000-4000-8000-000000000001';

-- Remove seed clan itself
DELETE FROM public.clans
WHERE id = 'c1000000-0000-4000-8000-000000000001';

-- Recompute ratings for remaining clans
DO $$
DECLARE r RECORD;
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc WHERE proname = 'recompute_clan_rating'
  ) THEN
    FOR r IN SELECT id FROM public.clans LOOP
      PERFORM public.recompute_clan_rating(r.id);
    END LOOP;
  END IF;
END $$;
