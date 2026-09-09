-- Fixed in-game roles (`profiles.game_role`) with icons in the app.

-- Normalize legacy free-text values to enum keys
UPDATE public.profiles
SET game_role = CASE lower(trim(game_role))
  WHEN 'штурмовик' THEN 'assault'
  WHEN 'штурм' THEN 'assault'
  WHEN 'assault' THEN 'assault'
  WHEN 'снайпер' THEN 'sniper'
  WHEN 'sniper' THEN 'sniper'
  WHEN 'медик' THEN 'medic'
  WHEN 'medic' THEN 'medic'
  WHEN 'разведчик' THEN 'recon'
  WHEN 'разведка' THEN 'recon'
  WHEN 'recon' THEN 'recon'
  WHEN 'пулемётчик' THEN 'support'
  WHEN 'пулеметчик' THEN 'support'
  WHEN 'поддержка' THEN 'support'
  WHEN 'support' THEN 'support'
  WHEN 'марксман' THEN 'marksman'
  WHEN 'dmr' THEN 'marksman'
  WHEN 'marksman' THEN 'marksman'
  WHEN 'гренадер' THEN 'grenadier'
  WHEN 'подрывник' THEN 'grenadier'
  WHEN 'grenadier' THEN 'grenadier'
  ELSE NULL
END
WHERE game_role IS NOT NULL
  AND trim(game_role) <> '';

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_game_role_check;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_game_role_check
  CHECK (
    game_role IS NULL
    OR game_role IN (
      'assault',
      'sniper',
      'medic',
      'recon',
      'support',
      'marksman',
      'grenadier'
    )
  );
