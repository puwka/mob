-- Public badge role for profiles: admin > organizer > user
CREATE OR REPLACE FUNCTION public.profile_badge_role(p_user_id UUID)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN EXISTS (
      SELECT 1 FROM public.admin_users au WHERE au.id = p_user_id
    ) THEN 'admin'
    WHEN (
      SELECT p.role FROM public.profiles p WHERE p.id = p_user_id
    ) = 'organizer' THEN 'organizer'
    ELSE 'user'
  END;
$$;

REVOKE ALL ON FUNCTION public.profile_badge_role(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.profile_badge_role(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.profile_badge_role(UUID) TO anon;
