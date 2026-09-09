-- ============================================================
-- Incoming like alerts + notify both sides on match + realtime
-- ============================================================

CREATE TABLE IF NOT EXISTS public.dating_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('like', 'match')),
  from_user_id UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  match_id UUID REFERENCES public.dating_matches (id) ON DELETE CASCADE,
  conversation_id UUID REFERENCES public.conversations (id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  seen_at TIMESTAMPTZ,
  CONSTRAINT dating_notifications_no_self CHECK (user_id <> from_user_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS dating_notifications_pair_kind_idx
  ON public.dating_notifications (user_id, from_user_id, kind);

CREATE INDEX IF NOT EXISTS dating_notifications_user_unseen_idx
  ON public.dating_notifications (user_id, created_at DESC)
  WHERE seen_at IS NULL;

ALTER TABLE public.dating_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Dating notifications select own" ON public.dating_notifications;
CREATE POLICY "Dating notifications select own"
  ON public.dating_notifications
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Dating notifications update own" ON public.dating_notifications;
CREATE POLICY "Dating notifications update own"
  ON public.dating_notifications
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Realtime for live delivery
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.dating_notifications;
  EXCEPTION
    WHEN duplicate_object THEN NULL;
    WHEN undefined_object THEN NULL;
  END;
END $$;

DROP FUNCTION IF EXISTS public.process_dating_action(UUID, TEXT);

CREATE OR REPLACE FUNCTION public.process_dating_action(
  p_target_user_id UUID,
  p_action TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_action TEXT := lower(btrim(COALESCE(p_action, '')));
  v_row public.dating_actions;
  v_matched BOOLEAN := FALSE;
  v_match_id UUID := NULL;
  v_conversation_id UUID := NULL;
  v_user1 UUID;
  v_user2 UUID;
  v_conv UUID;
  v_me public.profiles;
  v_other public.profiles;
  v_inserted BOOLEAN := FALSE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  IF p_target_user_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_TARGET' USING ERRCODE = 'P0001';
  END IF;

  IF p_target_user_id = v_uid THEN
    RAISE EXCEPTION 'CANNOT_ACTION_SELF' USING ERRCODE = 'P0001';
  END IF;

  IF v_action NOT IN ('like', 'skip') THEN
    RAISE EXCEPTION 'INVALID_ACTION' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_other FROM public.profiles WHERE id = p_target_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROFILE_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_me FROM public.profiles WHERE id = v_uid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROFILE_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF public.is_users_blocked(v_uid, p_target_user_id) THEN
    RAISE EXCEPTION 'USER_BLOCKED' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.dating_actions AS da (from_user_id, to_user_id, action)
  VALUES (v_uid, p_target_user_id, v_action)
  ON CONFLICT (from_user_id, to_user_id) DO NOTHING
  RETURNING da.* INTO v_row;

  IF FOUND THEN
    v_inserted := TRUE;
  ELSE
    SELECT da.* INTO v_row
    FROM public.dating_actions da
    WHERE da.from_user_id = v_uid AND da.to_user_id = p_target_user_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'ACTION_FAILED' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  -- Incoming like alert for the other user (only on newly inserted like).
  IF v_inserted AND v_row.action = 'like' THEN
    INSERT INTO public.dating_notifications (
      user_id, kind, from_user_id
    )
    VALUES (p_target_user_id, 'like', v_uid)
    ON CONFLICT (user_id, from_user_id, kind) DO NOTHING;
  END IF;

  IF v_action = 'like'
     AND v_row.action = 'like'
     AND NOT public.is_users_blocked(v_uid, p_target_user_id)
  THEN
    IF EXISTS (
      SELECT 1
      FROM public.dating_actions da
      WHERE da.from_user_id = p_target_user_id
        AND da.to_user_id = v_uid
        AND da.action = 'like'
    ) THEN
      IF v_uid < p_target_user_id THEN
        v_user1 := v_uid;
        v_user2 := p_target_user_id;
      ELSE
        v_user1 := p_target_user_id;
        v_user2 := v_uid;
      END IF;

      SELECT dm.id, dm.conversation_id
      INTO v_match_id, v_conversation_id
      FROM public.dating_matches dm
      WHERE dm.user1_id = v_user1 AND dm.user2_id = v_user2;

      IF v_match_id IS NULL THEN
        INSERT INTO public.dating_matches AS dm (user1_id, user2_id)
        VALUES (v_user1, v_user2)
        ON CONFLICT (user1_id, user2_id) DO NOTHING
        RETURNING dm.id INTO v_match_id;

        IF v_match_id IS NULL THEN
          SELECT dm.id, dm.conversation_id
          INTO v_match_id, v_conversation_id
          FROM public.dating_matches dm
          WHERE dm.user1_id = v_user1 AND dm.user2_id = v_user2;
        END IF;
      END IF;

      IF v_match_id IS NOT NULL THEN
        IF v_conversation_id IS NULL THEN
          BEGIN
            v_conv := public.dating_ensure_dating_chat(
              v_uid, p_target_user_id, v_match_id
            );
          EXCEPTION
            WHEN undefined_function THEN
              BEGIN
                v_conv := public.ensure_user_dm(p_target_user_id);
              EXCEPTION
                WHEN OTHERS THEN
                  v_conv := NULL;
              END;
            WHEN OTHERS THEN
              BEGIN
                v_conv := public.ensure_user_dm(p_target_user_id);
              EXCEPTION
                WHEN OTHERS THEN
                  v_conv := NULL;
              END;
          END;

          IF v_conv IS NOT NULL THEN
            UPDATE public.dating_matches
            SET conversation_id = v_conv
            WHERE id = v_match_id;

            BEGIN
              UPDATE public.conversations
              SET
                type = 'dating',
                dating_match_id = COALESCE(dating_match_id, v_match_id)
              WHERE id = v_conv;
            EXCEPTION
              WHEN OTHERS THEN
                NULL;
            END;

            v_conversation_id := v_conv;
          END IF;
        END IF;

        -- Match alerts for BOTH users.
        INSERT INTO public.dating_notifications (
          user_id, kind, from_user_id, match_id, conversation_id
        )
        VALUES
          (v_uid, 'match', p_target_user_id, v_match_id, v_conversation_id),
          (p_target_user_id, 'match', v_uid, v_match_id, v_conversation_id)
        ON CONFLICT (user_id, from_user_id, kind) DO UPDATE
        SET
          match_id = EXCLUDED.match_id,
          conversation_id = COALESCE(EXCLUDED.conversation_id, public.dating_notifications.conversation_id),
          seen_at = NULL,
          created_at = NOW();

        -- Mark mutual like alerts as seen (replaced by match).
        UPDATE public.dating_notifications
        SET seen_at = COALESCE(seen_at, NOW())
        WHERE kind = 'like'
          AND seen_at IS NULL
          AND (
            (user_id = v_uid AND from_user_id = p_target_user_id)
            OR (user_id = p_target_user_id AND from_user_id = v_uid)
          );

        -- Keep legacy table in sync for older clients.
        BEGIN
          INSERT INTO public.dating_match_notifications (match_id, user_id)
          VALUES
            (v_match_id, v_uid),
            (v_match_id, p_target_user_id)
          ON CONFLICT (match_id, user_id) DO NOTHING;
        EXCEPTION
          WHEN undefined_table THEN NULL;
        END;

        v_matched := TRUE;
      END IF;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'action_id', v_row.id,
    'from_user_id', v_row.from_user_id,
    'to_user_id', v_row.to_user_id,
    'action', v_row.action,
    'created_at', v_row.created_at,
    'inserted', v_inserted,
    'matched', v_matched,
    'match_id', v_match_id,
    'conversation_id', v_conversation_id,
    'me', jsonb_build_object(
      'id', v_me.id,
      'nickname', v_me.nickname,
      'city', v_me.city,
      'avatar_url', v_me.avatar_url
    ),
    'target', jsonb_build_object(
      'id', v_other.id,
      'nickname', v_other.nickname,
      'city', v_other.city,
      'avatar_url', v_other.avatar_url
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.process_dating_action(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_dating_action(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.dating_record_action(
  p_to_user_id UUID,
  p_action TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.process_dating_action(p_to_user_id, p_action);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_pending_dating_notifications()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  RETURN COALESCE(
    (
      SELECT jsonb_agg(row_data ORDER BY sort_key DESC)
      FROM (
        SELECT
          jsonb_build_object(
            'notification_id', n.id,
            'kind', n.kind,
            'match_id', n.match_id,
            'conversation_id', n.conversation_id,
            'created_at', n.created_at,
            'me', jsonb_build_object(
              'id', me.id,
              'nickname', me.nickname,
              'city', me.city,
              'avatar_url', me.avatar_url
            ),
            'other', jsonb_build_object(
              'id', oth.id,
              'nickname', oth.nickname,
              'city', oth.city,
              'avatar_url', oth.avatar_url
            )
          ) AS row_data,
          n.created_at AS sort_key
        FROM public.dating_notifications n
        JOIN public.profiles me ON me.id = v_uid
        JOIN public.profiles oth ON oth.id = n.from_user_id
        WHERE n.user_id = v_uid
          AND n.seen_at IS NULL
          AND NOT public.is_users_blocked(v_uid, oth.id)
        ORDER BY
          CASE n.kind WHEN 'match' THEN 0 ELSE 1 END,
          n.created_at DESC
        LIMIT 20
      ) rows
    ),
    '[]'::jsonb
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_pending_dating_notifications() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_pending_dating_notifications() TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_dating_notification_seen(p_notification_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  UPDATE public.dating_notifications
  SET seen_at = NOW()
  WHERE id = p_notification_id
    AND user_id = v_uid
    AND seen_at IS NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_dating_notification_seen(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_dating_notification_seen(UUID) TO authenticated;

-- Back-compat wrappers used by older Flutter builds
CREATE OR REPLACE FUNCTION public.get_pending_dating_match_notifications()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN (
    SELECT COALESCE(jsonb_agg(x), '[]'::jsonb)
    FROM (
      SELECT elem
      FROM jsonb_array_elements(public.get_pending_dating_notifications()) elem
      WHERE elem->>'kind' = 'match'
    ) q(x)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_dating_match_notification_seen(
  p_notification_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.mark_dating_notification_seen(p_notification_id);
END;
$$;

-- Repair: create matches + alerts for already mutual likes without a match row.
DO $$
DECLARE
  r RECORD;
  v_user1 UUID;
  v_user2 UUID;
  v_match_id UUID;
  v_conv UUID;
BEGIN
  FOR r IN
    SELECT a.from_user_id AS a_id, a.to_user_id AS b_id
    FROM public.dating_actions a
    JOIN public.dating_actions b
      ON b.from_user_id = a.to_user_id
     AND b.to_user_id = a.from_user_id
     AND b.action = 'like'
    WHERE a.action = 'like'
      AND a.from_user_id < a.to_user_id
  LOOP
    v_user1 := r.a_id;
    v_user2 := r.b_id;

    SELECT id INTO v_match_id
    FROM public.dating_matches
    WHERE user1_id = v_user1 AND user2_id = v_user2;

    IF v_match_id IS NULL THEN
      INSERT INTO public.dating_matches (user1_id, user2_id)
      VALUES (v_user1, v_user2)
      RETURNING id INTO v_match_id;
    END IF;

    SELECT conversation_id INTO v_conv
    FROM public.dating_matches WHERE id = v_match_id;

    IF v_conv IS NULL THEN
      BEGIN
        v_conv := public.dating_ensure_dating_chat(v_user1, v_user2, v_match_id);
      EXCEPTION
        WHEN OTHERS THEN
          v_conv := NULL;
      END;
      IF v_conv IS NOT NULL THEN
        UPDATE public.dating_matches SET conversation_id = v_conv WHERE id = v_match_id;
      END IF;
    END IF;

    INSERT INTO public.dating_notifications (
      user_id, kind, from_user_id, match_id, conversation_id
    )
    VALUES
      (v_user1, 'match', v_user2, v_match_id, v_conv),
      (v_user2, 'match', v_user1, v_match_id, v_conv)
    ON CONFLICT (user_id, from_user_id, kind) DO UPDATE
    SET
      match_id = EXCLUDED.match_id,
      conversation_id = COALESCE(EXCLUDED.conversation_id, public.dating_notifications.conversation_id),
      seen_at = NULL,
      created_at = NOW();
  END LOOP;
END $$;

-- Backfill one-way likes that never notified the target.
INSERT INTO public.dating_notifications (user_id, kind, from_user_id)
SELECT da.to_user_id, 'like', da.from_user_id
FROM public.dating_actions da
WHERE da.action = 'like'
  AND NOT EXISTS (
    SELECT 1 FROM public.dating_matches dm
    WHERE (dm.user1_id = da.from_user_id AND dm.user2_id = da.to_user_id)
       OR (dm.user2_id = da.from_user_id AND dm.user1_id = da.to_user_id)
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.dating_actions back
    WHERE back.from_user_id = da.to_user_id
      AND back.to_user_id = da.from_user_id
      AND back.action = 'like'
  )
ON CONFLICT (user_id, from_user_id, kind) DO NOTHING;

NOTIFY pgrst, 'reload schema';
