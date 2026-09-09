-- Badge: admin/super_admin → admin, moderator → moderator, else organizer/user
CREATE OR REPLACE FUNCTION public.profile_badge_role(p_user_id UUID)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN EXISTS (
      SELECT 1 FROM public.admin_users au
      WHERE au.id = p_user_id AND au.role IN ('super_admin', 'admin')
    ) THEN 'admin'
    WHEN EXISTS (
      SELECT 1 FROM public.admin_users au
      WHERE au.id = p_user_id AND au.role = 'moderator'
    ) THEN 'moderator'
    WHEN (
      SELECT p.role FROM public.profiles p WHERE p.id = p_user_id
    ) = 'organizer' THEN 'organizer'
    ELSE 'user'
  END;
$$;

NOTIFY pgrst, 'reload schema';
