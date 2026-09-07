-- ========== BLOCK F: messaging RLS + dialog RPCs ==========
-- Run after 01 + 02.

DROP POLICY IF EXISTS "Admins read conversations" ON public.conversations;
CREATE POLICY "Admins read conversations"
  ON public.conversations FOR SELECT TO authenticated
  USING (public.admin_has_perm('dialogs'));

DROP POLICY IF EXISTS "Admins read conversation members" ON public.conversation_members;
CREATE POLICY "Admins read conversation members"
  ON public.conversation_members FOR SELECT TO authenticated
  USING (public.admin_has_perm('dialogs'));

DROP POLICY IF EXISTS "Admins read messages" ON public.messages;
CREATE POLICY "Admins read messages"
  ON public.messages FOR SELECT TO authenticated
  USING (public.admin_has_perm('dialogs'));
