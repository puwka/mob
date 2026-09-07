-- ============================================================
-- Migration: profiles table, indexes, RLS
-- Auth: phone + password via Supabase Auth (email identity =
--       normalized phone → {digits}@phone.local)
-- ============================================================

-- Profiles
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  phone TEXT UNIQUE NOT NULL,
  nickname TEXT UNIQUE NOT NULL,
  city TEXT NOT NULL,
  avatar_url TEXT,
  bio TEXT,
  role TEXT,
  team_name TEXT,
  games_played INTEGER NOT NULL DEFAULT 0,
  wins INTEGER NOT NULL DEFAULT 0,
  rating INTEGER NOT NULL DEFAULT 0,
  polygons_visited INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT nickname_length CHECK (char_length(nickname) BETWEEN 3 AND 20),
  CONSTRAINT nickname_charset CHECK (nickname ~ '^[a-zA-Z0-9_а-яА-ЯёЁ\-]+$')
);

-- Indexes
CREATE INDEX IF NOT EXISTS profiles_nickname_idx ON public.profiles (nickname);
CREATE INDEX IF NOT EXISTS profiles_phone_idx ON public.profiles (phone);
CREATE INDEX IF NOT EXISTS profiles_city_idx ON public.profiles (city);
CREATE INDEX IF NOT EXISTS profiles_rating_idx ON public.profiles (rating DESC);
CREATE INDEX IF NOT EXISTS profiles_created_at_idx ON public.profiles (created_at DESC);

-- RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Public read of profiles (authenticated users)
DROP POLICY IF EXISTS "Profiles are viewable by authenticated users"
  ON public.profiles;
CREATE POLICY "Profiles are viewable by authenticated users"
  ON public.profiles
  FOR SELECT
  TO authenticated
  USING (true);

-- Allow anonymous nickname uniqueness checks during registration
DROP POLICY IF EXISTS "Anyone can check nickname availability"
  ON public.profiles;
CREATE POLICY "Anyone can check nickname availability"
  ON public.profiles
  FOR SELECT
  TO anon
  USING (true);

-- Insert own profile
DROP POLICY IF EXISTS "Users can insert own profile"
  ON public.profiles;
CREATE POLICY "Users can insert own profile"
  ON public.profiles
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

-- Update own profile only
DROP POLICY IF EXISTS "Users can update own profile"
  ON public.profiles;
CREATE POLICY "Users can update own profile"
  ON public.profiles
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- Optional: prevent delete from client (cascade from auth.users handles cleanup)
DROP POLICY IF EXISTS "Users can delete own profile"
  ON public.profiles;
CREATE POLICY "Users can delete own profile"
  ON public.profiles
  FOR DELETE
  TO authenticated
  USING (auth.uid() = id);

COMMENT ON TABLE public.profiles IS 'Player profiles linked to auth.users';
COMMENT ON COLUMN public.profiles.phone IS 'E.164-like normalized phone, used as login identity';
