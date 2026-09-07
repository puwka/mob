-- ============================================================
-- SAFE APPLY: run EACH block separately in SQL Editor
-- (select → Run). Do NOT paste the whole file at once if
-- the DB is under load. Close other SQL tabs / pause apps.
-- Idempotent: safe to re-run after a deadlock abort.
-- ============================================================

-- ========== BLOCK A: conversations.status ==========
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS status TEXT;

UPDATE public.conversations
SET status = 'active'
WHERE status IS NULL;

ALTER TABLE public.conversations
  ALTER COLUMN status SET DEFAULT 'active';

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.conversations WHERE status IS NULL
  ) THEN
    UPDATE public.conversations SET status = 'active' WHERE status IS NULL;
  END IF;
END $$;

ALTER TABLE public.conversations
  ALTER COLUMN status SET NOT NULL;

ALTER TABLE public.conversations DROP CONSTRAINT IF EXISTS conversations_status_check;
ALTER TABLE public.conversations
  ADD CONSTRAINT conversations_status_check
  CHECK (status IN ('active', 'blocked', 'archived'));

CREATE INDEX IF NOT EXISTS conversations_status_idx
  ON public.conversations (status);
CREATE INDEX IF NOT EXISTS conversations_type_idx
  ON public.conversations (type);

-- ========== BLOCK B: messages.deleted_by ==========
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS deleted_by UUID;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'messages_deleted_by_fkey'
  ) THEN
    ALTER TABLE public.messages
      ADD CONSTRAINT messages_deleted_by_fkey
      FOREIGN KEY (deleted_by) REFERENCES public.admin_users (id)
      ON DELETE SET NULL
      NOT VALID;
    ALTER TABLE public.messages
      VALIDATE CONSTRAINT messages_deleted_by_fkey;
  END IF;
END $$;

-- ========== BLOCK C: app_settings seed ==========
INSERT INTO public.app_settings (key, value) VALUES
  ('organizer_attendance_reward', '100'),
  ('event_creation_fee', '0'),
  ('withdrawal_fee', '0'),
  ('profile_photos_limit', '4'),
  ('listing_images_limit', '8'),
  ('message_max_length', '4000'),
  ('listing_default_status', 'pending'),
  ('moderation_required', 'true'),
  ('event_default_max_participants', '20')
ON CONFLICT (key) DO NOTHING;

-- ========== BLOCK D: admin_notifications ==========
CREATE TABLE IF NOT EXISTS public.admin_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  type TEXT NOT NULL
    CHECK (type IN (
      'all_users', 'organizers', 'city_users', 'event_participants', 'clan_members'
    )),
  target_city TEXT,
  target_event_id UUID REFERENCES public.events (id) ON DELETE SET NULL,
  target_clan_id UUID REFERENCES public.clans (id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'queued', 'sent', 'failed')),
  created_by UUID REFERENCES public.admin_users (id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sent_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS admin_notifications_created_idx
  ON public.admin_notifications (created_at DESC);

ALTER TABLE public.admin_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins read notifications" ON public.admin_notifications;
CREATE POLICY "Admins read notifications"
  ON public.admin_notifications FOR SELECT TO authenticated
  USING (public.is_admin());
