-- ============================================================
-- Fix process_dating_action: uninitialized v_match crashed every like/skip
-- ============================================================

CREATE OR REPLACE FUNCTION public.process_dating_action(
  target_user_id UUID,
  action TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_action TEXT := lower(btrim(COALESCE(action, '')));
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

  IF target_user_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_TARGET' USING ERRCODE = 'P0001';
  END IF;

  IF target_user_id = v_uid THEN
    RAISE EXCEPTION 'CANNOT_ACTION_SELF' USING ERRCODE = 'P0001';
  END IF;

  IF v_action NOT IN ('like', 'skip') THEN
    RAISE EXCEPTION 'INVALID_ACTION' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_other FROM public.profiles WHERE id = target_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROFILE_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_me FROM public.profiles WHERE id = v_uid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROFILE_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF public.is_users_blocked(v_uid, target_user_id) THEN
    RAISE EXCEPTION 'USER_BLOCKED' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.dating_actions (from_user_id, to_user_id, action)
  VALUES (v_uid, target_user_id, v_action)
  ON CONFLICT (from_user_id, to_user_id) DO NOTHING
  RETURNING * INTO v_row;

  IF FOUND THEN
    v_inserted := TRUE;
  ELSE
    SELECT * INTO v_row
    FROM public.dating_actions
    WHERE from_user_id = v_uid AND to_user_id = target_user_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'ACTION_FAILED' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  IF v_action = 'like'
     AND v_row.action = 'like'
     AND NOT public.is_users_blocked(v_uid, target_user_id)
  THEN
    IF EXISTS (
      SELECT 1
      FROM public.dating_actions
      WHERE from_user_id = target_user_id
        AND to_user_id = v_uid
        AND action = 'like'
    ) THEN
      IF v_uid < target_user_id THEN
        v_user1 := v_uid;
        v_user2 := target_user_id;
      ELSE
        v_user1 := target_user_id;
        v_user2 := v_uid;
      END IF;

      SELECT id, conversation_id
      INTO v_match_id, v_conversation_id
      FROM public.dating_matches
      WHERE user1_id = v_user1 AND user2_id = v_user2;

      IF v_match_id IS NULL THEN
        INSERT INTO public.dating_matches (user1_id, user2_id)
        VALUES (v_user1, v_user2)
        ON CONFLICT (user1_id, user2_id) DO NOTHING
        RETURNING id INTO v_match_id;

        IF v_match_id IS NULL THEN
          SELECT id, conversation_id
          INTO v_match_id, v_conversation_id
          FROM public.dating_matches
          WHERE user1_id = v_user1 AND user2_id = v_user2;
        END IF;
      END IF;

      IF v_match_id IS NOT NULL THEN
        IF v_conversation_id IS NULL THEN
          -- Prefer dating chat helper when available; fall back to user DM.
          BEGIN
            v_conv := public.dating_ensure_dating_chat(
              v_uid, target_user_id, v_match_id
            );
          EXCEPTION
            WHEN undefined_function THEN
              v_conv := public.dating_ensure_dm(v_uid, target_user_id);
            WHEN OTHERS THEN
              BEGIN
                v_conv := public.ensure_user_dm(target_user_id);
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
                NULL; -- keep DM even if dating columns/type not migrated yet
            END;

            v_conversation_id := v_conv;
          END IF;
        END IF;

        INSERT INTO public.dating_match_notifications (match_id, user_id)
        VALUES (v_match_id, target_user_id)
        ON CONFLICT (match_id, user_id) DO NOTHING;

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

REVOKE ALL ON FUNCTION public.dating_record_action(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dating_record_action(UUID, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
