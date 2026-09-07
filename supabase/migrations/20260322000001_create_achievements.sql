-- ============================================================
-- Achievements catalog + user progress
-- ============================================================

CREATE TABLE IF NOT EXISTS public.achievements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  icon TEXT NOT NULL,
  type TEXT NOT NULL,
  required_value INTEGER NOT NULL CHECK (required_value > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT achievements_type_check CHECK (
    type IN ('games_played', 'wins', 'polygons_visited', 'rating')
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS achievements_title_uidx
  ON public.achievements (title);

CREATE INDEX IF NOT EXISTS achievements_type_idx
  ON public.achievements (type);

CREATE TABLE IF NOT EXISTS public.user_achievements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  achievement_id UUID NOT NULL REFERENCES public.achievements (id) ON DELETE CASCADE,
  progress INTEGER NOT NULL DEFAULT 0 CHECK (progress >= 0),
  unlocked BOOLEAN NOT NULL DEFAULT FALSE,
  unlocked_at TIMESTAMPTZ,
  UNIQUE (user_id, achievement_id)
);

CREATE INDEX IF NOT EXISTS user_achievements_user_idx
  ON public.user_achievements (user_id);

CREATE INDEX IF NOT EXISTS user_achievements_unlocked_idx
  ON public.user_achievements (user_id, unlocked);

-- RLS
ALTER TABLE public.achievements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_achievements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Achievements readable by authenticated"
  ON public.achievements;
CREATE POLICY "Achievements readable by authenticated"
  ON public.achievements
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Achievements readable by anon"
  ON public.achievements;
CREATE POLICY "Achievements readable by anon"
  ON public.achievements
  FOR SELECT
  TO anon
  USING (true);

DROP POLICY IF EXISTS "Users read own achievement progress"
  ON public.user_achievements;
CREATE POLICY "Users read own achievement progress"
  ON public.user_achievements
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users insert own achievement progress"
  ON public.user_achievements;
CREATE POLICY "Users insert own achievement progress"
  ON public.user_achievements
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users update own achievement progress"
  ON public.user_achievements;
CREATE POLICY "Users update own achievement progress"
  ON public.user_achievements
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Seed (idempotent by title)
INSERT INTO public.achievements (title, description, icon, type, required_value)
VALUES
  ('Ветеран', 'Сыграть 50 игр', 'veteran', 'games_played', 50),
  ('Тактик', 'Одержать 10 побед', 'tactician', 'wins', 10),
  ('Мастер', 'Сыграть 100 игр', 'master', 'games_played', 100),
  ('Командный игрок', 'Сыграть 25 игр', 'teammate', 'games_played', 25),
  ('Путешественник', 'Посетить 5 полигонов', 'traveler', 'polygons_visited', 5)
ON CONFLICT (title) DO UPDATE
SET
  description = EXCLUDED.description,
  icon = EXCLUDED.icon,
  type = EXCLUDED.type,
  required_value = EXCLUDED.required_value;
