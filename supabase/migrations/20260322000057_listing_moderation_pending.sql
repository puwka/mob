-- ============================================================
-- Listings must go through moderation (pending) on create
-- ============================================================

ALTER TABLE public.listings
  ALTER COLUMN status SET DEFAULT 'pending';

CREATE OR REPLACE FUNCTION public.protect_listing_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- Non-admins cannot publish directly
    IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
      NEW.status := 'pending';
    ELSIF auth.uid() IS NULL THEN
      NEW.status := 'pending';
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    NEW.seller_id = OLD.seller_id;

    IF NEW.views_count IS DISTINCT FROM OLD.views_count
       AND NEW.views_count <> OLD.views_count + 1 THEN
      NEW.views_count = OLD.views_count;
    END IF;

    -- Sellers cannot self-approve to active
    IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
      IF NEW.status IS DISTINCT FROM OLD.status THEN
        IF NOT (
          (OLD.status = 'active' AND NEW.status IN ('sold', 'archived'))
          OR (OLD.status IN ('pending', 'rejected') AND NEW.status = 'archived')
          OR (OLD.status = 'rejected' AND NEW.status = 'pending')
        ) THEN
          NEW.status := OLD.status;
        END IF;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS listings_protect_fields ON public.listings;
CREATE TRIGGER listings_protect_fields
  BEFORE INSERT OR UPDATE ON public.listings
  FOR EACH ROW
  EXECUTE PROCEDURE public.protect_listing_fields();

NOTIFY pgrst, 'reload schema';
