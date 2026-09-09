-- ============================================================
-- DEV SEED: 20 dating test users with avatars + gallery photos
-- Run in Supabase → SQL Editor (as postgres).
-- Idempotent: safe to re-run.
--
-- Phone / auth email: 79009000001 … 79009000020 → *@phone.local
-- Password: Test1234!
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
DECLARE
  v_ids UUID[] := ARRAY[
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
  ];
  v_nicks TEXT[] := ARRAY[
    'Voron', 'Yastreb', 'Lisa', 'Volk', 'Bars',
    'Oryol', 'Tigr', 'Sobol', 'Rys', 'Korshun',
    'Feniks', 'Sokol', 'Medved', 'Ris', 'Puma',
    'Gepard', 'Kobalt', 'Storm', 'Shadow', 'Reaper'
  ];
  v_cities TEXT[] := ARRAY[
    'Москва', 'Санкт-Петербург', 'Казань', 'Новосибирск', 'Екатеринбург',
    'Москва', 'Краснодар', 'Нижний Новгород', 'Самара', 'Ростов-на-Дону',
    'Москва', 'Воронеж', 'Пермь', 'Уфа', 'Челябинск',
    'Санкт-Петербург', 'Казань', 'Москва', 'Тула', 'Ярославль'
  ];
  i INTEGER;
  v_id UUID;
  v_email TEXT;
  v_phone TEXT;
  v_pass TEXT;
  v_avatar TEXT;
BEGIN
  v_pass := crypt('Test1234!', gen_salt('bf'));

  -- Remove previous seed users (profiles / photos cascade)
  DELETE FROM auth.identities WHERE user_id = ANY (v_ids);
  DELETE FROM auth.users WHERE id = ANY (v_ids);

  FOR i IN 1..20 LOOP
    v_id := v_ids[i];
    v_phone := '7900900' || lpad(i::text, 4, '0');
    v_email := v_phone || '@phone.local';
    v_avatar := 'https://picsum.photos/seed/ms_dating_' || i::text || '/900/1200';

    INSERT INTO auth.users (
      instance_id,
      id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at
    ) VALUES (
      COALESCE(
        (SELECT id FROM auth.instances LIMIT 1),
        '00000000-0000-0000-0000-000000000000'::uuid
      ),
      v_id,
      'authenticated',
      'authenticated',
      v_email,
      v_pass,
      NOW(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('nickname', v_nicks[i], 'city', v_cities[i]),
      NOW() - make_interval(hours => i),
      NOW()
    );

    INSERT INTO auth.identities (
      id,
      user_id,
      identity_data,
      provider,
      provider_id,
      last_sign_in_at,
      created_at,
      updated_at
    ) VALUES (
      gen_random_uuid(),
      v_id,
      jsonb_build_object(
        'sub', v_id::text,
        'email', v_email,
        'email_verified', true
      ),
      'email',
      v_email,
      NOW(),
      NOW(),
      NOW()
    );

    INSERT INTO public.profiles (
      id,
      phone,
      nickname,
      city,
      avatar_url,
      bio,
      game_role,
      team_name,
      role,
      games_played,
      wins,
      rating,
      polygons_visited,
      created_at
    ) VALUES (
      v_id,
      v_phone,
      v_nicks[i],
      v_cities[i],
      v_avatar,
      'Тестовая анкета для Знакомств #' || i::text,
      CASE (i % 4)
        WHEN 0 THEN 'Штурмовик'
        WHEN 1 THEN 'Снайпер'
        WHEN 2 THEN 'Поддержка'
        ELSE 'Разведчик'
      END,
      'SeedTeam',
      'user',
      5 + i,
      i % 5,
      (5 + i) * 100 + (i % 5) * 250,
      i % 7,
      NOW() - make_interval(hours => i)
    );

    INSERT INTO public.profile_photos (user_id, url, sort_order) VALUES
      (v_id, 'https://picsum.photos/seed/ms_dating_' || i::text || '_g0/900/1200', 0),
      (v_id, 'https://picsum.photos/seed/ms_dating_' || i::text || '_g1/900/1200', 1),
      (v_id, 'https://picsum.photos/seed/ms_dating_' || i::text || '_g2/900/1200', 2);
  END LOOP;
END $$;

-- Verify
SELECT
  p.nickname,
  p.city,
  left(p.avatar_url, 40) AS avatar,
  (SELECT COUNT(*) FROM public.profile_photos pp WHERE pp.user_id = p.id) AS gallery
FROM public.profiles p
WHERE p.id BETWEEN
  'a1000000-0000-4000-8000-000000000001'::uuid
  AND 'a1000000-0000-4000-8000-000000000020'::uuid
ORDER BY p.nickname;
