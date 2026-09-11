-- ============================================================
-- CLEANUP: remove dating seed users from seed_dating_test_users.sql
-- Run in Supabase → SQL Editor (as postgres).
-- Idempotent: safe to re-run.
--
-- Targets fixed UUIDs a1000000-…-0001 … 0020
-- phones 79009000001 … 79009000020 / *@phone.local
-- nicknames from seed + team_name = SeedTeam
-- ============================================================

DO $$
DECLARE
  v_ids UUID[];
  v_deleted_profiles INT := 0;
  v_deleted_auth INT := 0;
BEGIN
  SELECT ARRAY(
    SELECT DISTINCT id FROM (
      SELECT unnest(ARRAY[
        'a1000000-0000-4000-8000-000000000001'::uuid,
        'a1000000-0000-4000-8000-000000000002'::uuid,
        'a1000000-0000-4000-8000-000000000003'::uuid,
        'a1000000-0000-4000-8000-000000000004'::uuid,
        'a1000000-0000-4000-8000-000000000005'::uuid,
        'a1000000-0000-4000-8000-000000000006'::uuid,
        'a1000000-0000-4000-8000-000000000007'::uuid,
        'a1000000-0000-4000-8000-000000000008'::uuid,
        'a1000000-0000-4000-8000-000000000009'::uuid,
        'a1000000-0000-4000-8000-000000000010'::uuid,
        'a1000000-0000-4000-8000-000000000011'::uuid,
        'a1000000-0000-4000-8000-000000000012'::uuid,
        'a1000000-0000-4000-8000-000000000013'::uuid,
        'a1000000-0000-4000-8000-000000000014'::uuid,
        'a1000000-0000-4000-8000-000000000015'::uuid,
        'a1000000-0000-4000-8000-000000000016'::uuid,
        'a1000000-0000-4000-8000-000000000017'::uuid,
        'a1000000-0000-4000-8000-000000000018'::uuid,
        'a1000000-0000-4000-8000-000000000019'::uuid,
        'a1000000-0000-4000-8000-000000000020'::uuid
      ]) AS id
      UNION
      SELECT id FROM public.profiles
      WHERE phone ~ '^7900900\d{4}$'
         OR (
           team_name = 'SeedTeam'
           AND nickname IN (
             'Voron', 'Yastreb', 'Lisa', 'Volk', 'Bars',
             'Oryol', 'Tigr', 'Sobol', 'Rys', 'Korshun',
             'Feniks', 'Sokol', 'Medved', 'Ris', 'Puma',
             'Gepard', 'Kobalt', 'Storm', 'Shadow', 'Reaper'
           )
         )
      UNION
      SELECT id FROM auth.users
      WHERE email ~ '^7900900\d{4}@phone\.local$'
    ) s
  ) INTO v_ids;

  IF v_ids IS NULL OR cardinality(v_ids) = 0 THEN
    RAISE NOTICE 'No seed dating users found.';
    RETURN;
  END IF;

  -- Chat membership / messages
  DELETE FROM public.conversation_members WHERE user_id = ANY (v_ids);
  DELETE FROM public.messages WHERE sender_id = ANY (v_ids);

  -- Dating
  DELETE FROM public.dating_actions
  WHERE from_user_id = ANY (v_ids) OR to_user_id = ANY (v_ids);

  DELETE FROM public.dating_matches
  WHERE user1_id = ANY (v_ids) OR user2_id = ANY (v_ids);

  IF to_regclass('public.user_blocks') IS NOT NULL THEN
    DELETE FROM public.user_blocks
    WHERE user_id = ANY (v_ids) OR blocked_user_id = ANY (v_ids);
  END IF;

  IF to_regclass('public.dating_reports') IS NOT NULL THEN
    EXECUTE
      'DELETE FROM public.dating_reports
       WHERE reporter_id = ANY ($1) OR target_user_id = ANY ($1)'
    USING v_ids;
  END IF;

  IF to_regclass('public.dating_notifications') IS NOT NULL THEN
    DELETE FROM public.dating_notifications
    WHERE user_id = ANY (v_ids) OR from_user_id = ANY (v_ids);
  END IF;

  IF to_regclass('public.dating_match_notifications') IS NOT NULL THEN
    DELETE FROM public.dating_match_notifications
    WHERE user_id = ANY (v_ids);
  END IF;

  IF to_regclass('public.dating_preferences') IS NOT NULL THEN
    DELETE FROM public.dating_preferences WHERE user_id = ANY (v_ids);
  END IF;

  IF to_regclass('public.profile_photos') IS NOT NULL THEN
    DELETE FROM public.profile_photos WHERE user_id = ANY (v_ids);
  END IF;

  -- Listings / favorites owned by seed users
  IF to_regclass('public.listing_favorites') IS NOT NULL THEN
    DELETE FROM public.listing_favorites WHERE user_id = ANY (v_ids);
  END IF;

  IF to_regclass('public.listings') IS NOT NULL THEN
    DELETE FROM public.listings WHERE seller_id = ANY (v_ids);
  END IF;

  IF to_regclass('public.clan_members') IS NOT NULL THEN
    DELETE FROM public.clan_members WHERE user_id = ANY (v_ids);
  END IF;

  DELETE FROM public.profiles WHERE id = ANY (v_ids);
  GET DIAGNOSTICS v_deleted_profiles = ROW_COUNT;

  DELETE FROM auth.identities WHERE user_id = ANY (v_ids);
  DELETE FROM auth.users WHERE id = ANY (v_ids);
  GET DIAGNOSTICS v_deleted_auth = ROW_COUNT;

  RAISE NOTICE
    'Seed dating cleanup done. profiles=%, auth.users=%',
    v_deleted_profiles, v_deleted_auth;
END $$;

SELECT COUNT(*) AS remaining_seed_profiles
FROM public.profiles
WHERE id BETWEEN
        'a1000000-0000-4000-8000-000000000001'::uuid
    AND 'a1000000-0000-4000-8000-000000000020'::uuid
   OR (team_name = 'SeedTeam' AND phone ~ '^7900900\d{4}$');

SELECT COUNT(*) AS remaining_seed_auth
FROM auth.users
WHERE email ~ '^7900900\d{4}@phone\.local$'
   OR id BETWEEN
        'a1000000-0000-4000-8000-000000000001'::uuid
    AND 'a1000000-0000-4000-8000-000000000020'::uuid;
