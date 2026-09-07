-- ============================================================
-- Marketplace: categories, listings, images, favorites
-- ============================================================

CREATE TABLE IF NOT EXISTS public.categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  parent_id UUID REFERENCES public.categories (id) ON DELETE CASCADE,
  icon TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS categories_parent_idx ON public.categories (parent_id);
CREATE INDEX IF NOT EXISTS categories_sort_idx ON public.categories (sort_order);

CREATE TABLE IF NOT EXISTS public.listings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_id UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  category_id UUID NOT NULL REFERENCES public.categories (id) ON DELETE RESTRICT,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  price NUMERIC(12, 2) NOT NULL CHECK (price >= 0),
  city TEXT NOT NULL,
  condition TEXT NOT NULL DEFAULT 'used'
    CHECK (condition IN ('new', 'like_new', 'used')),
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('pending', 'active', 'sold', 'archived', 'rejected')),
  views_count INTEGER NOT NULL DEFAULT 0 CHECK (views_count >= 0),
  is_promoted BOOLEAN NOT NULL DEFAULT FALSE,
  promoted_until TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS listings_seller_idx ON public.listings (seller_id);
CREATE INDEX IF NOT EXISTS listings_category_idx ON public.listings (category_id);
CREATE INDEX IF NOT EXISTS listings_city_idx ON public.listings (city);
CREATE INDEX IF NOT EXISTS listings_status_idx ON public.listings (status);
CREATE INDEX IF NOT EXISTS listings_price_idx ON public.listings (price);
CREATE INDEX IF NOT EXISTS listings_created_idx ON public.listings (created_at DESC);
CREATE INDEX IF NOT EXISTS listings_promoted_idx
  ON public.listings (is_promoted, promoted_until)
  WHERE is_promoted = TRUE;
CREATE INDEX IF NOT EXISTS listings_active_feed_idx
  ON public.listings (status, city, created_at DESC)
  WHERE status = 'active';

CREATE TABLE IF NOT EXISTS public.listing_images (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id UUID NOT NULL REFERENCES public.listings (id) ON DELETE CASCADE,
  url TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS listing_images_listing_idx
  ON public.listing_images (listing_id, sort_order);

CREATE TABLE IF NOT EXISTS public.listing_favorites (
  user_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  listing_id UUID NOT NULL REFERENCES public.listings (id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, listing_id)
);

CREATE INDEX IF NOT EXISTS listing_favorites_listing_idx
  ON public.listing_favorites (listing_id);
CREATE INDEX IF NOT EXISTS listing_favorites_user_idx
  ON public.listing_favorites (user_id, created_at DESC);

-- updated_at trigger
CREATE OR REPLACE FUNCTION public.set_listings_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS listings_set_updated_at ON public.listings;
CREATE TRIGGER listings_set_updated_at
  BEFORE UPDATE ON public.listings
  FOR EACH ROW
  EXECUTE PROCEDURE public.set_listings_updated_at();

-- Protect seller_id; views may only increase by +1 (RPC)
CREATE OR REPLACE FUNCTION public.protect_listing_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    NEW.seller_id = OLD.seller_id;
    IF NEW.views_count IS DISTINCT FROM OLD.views_count
       AND NEW.views_count <> OLD.views_count + 1 THEN
      NEW.views_count = OLD.views_count;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS listings_protect_fields ON public.listings;
CREATE TRIGGER listings_protect_fields
  BEFORE UPDATE ON public.listings
  FOR EACH ROW
  EXECUTE PROCEDURE public.protect_listing_fields();

-- Increment views (authenticated, not seller)
CREATE OR REPLACE FUNCTION public.increment_listing_views(p_listing_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_seller UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT seller_id INTO v_seller
  FROM public.listings
  WHERE id = p_listing_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF v_seller = v_uid THEN
    RETURN;
  END IF;

  UPDATE public.listings
  SET views_count = views_count + 1
  WHERE id = p_listing_id;
END;
$$;

REVOKE ALL ON FUNCTION public.increment_listing_views(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.increment_listing_views(UUID) TO authenticated;

-- ============================================================
-- RLS
-- ============================================================

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.listings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.listing_images ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.listing_favorites ENABLE ROW LEVEL SECURITY;

-- Categories: read-only for authenticated
DROP POLICY IF EXISTS "Categories readable by authenticated" ON public.categories;
CREATE POLICY "Categories readable by authenticated"
  ON public.categories
  FOR SELECT
  TO authenticated
  USING (true);

-- Listings
DROP POLICY IF EXISTS "Active listings readable" ON public.listings;
CREATE POLICY "Active listings readable"
  ON public.listings
  FOR SELECT
  TO authenticated
  USING (
    status = 'active'
    OR seller_id = auth.uid()
  );

DROP POLICY IF EXISTS "Users can create listings" ON public.listings;
CREATE POLICY "Users can create listings"
  ON public.listings
  FOR INSERT
  TO authenticated
  WITH CHECK (seller_id = auth.uid());

DROP POLICY IF EXISTS "Users can update own listings" ON public.listings;
CREATE POLICY "Users can update own listings"
  ON public.listings
  FOR UPDATE
  TO authenticated
  USING (seller_id = auth.uid())
  WITH CHECK (seller_id = auth.uid());

DROP POLICY IF EXISTS "Users can delete own listings" ON public.listings;
CREATE POLICY "Users can delete own listings"
  ON public.listings
  FOR DELETE
  TO authenticated
  USING (seller_id = auth.uid());

-- Images: readable with listing; writable by seller
DROP POLICY IF EXISTS "Listing images readable" ON public.listing_images;
CREATE POLICY "Listing images readable"
  ON public.listing_images
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.listings l
      WHERE l.id = listing_id
        AND (l.status = 'active' OR l.seller_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "Sellers can insert listing images" ON public.listing_images;
CREATE POLICY "Sellers can insert listing images"
  ON public.listing_images
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.listings l
      WHERE l.id = listing_id AND l.seller_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Sellers can update listing images" ON public.listing_images;
CREATE POLICY "Sellers can update listing images"
  ON public.listing_images
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.listings l
      WHERE l.id = listing_id AND l.seller_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.listings l
      WHERE l.id = listing_id AND l.seller_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Sellers can delete listing images" ON public.listing_images;
CREATE POLICY "Sellers can delete listing images"
  ON public.listing_images
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.listings l
      WHERE l.id = listing_id AND l.seller_id = auth.uid()
    )
  );

-- Favorites
DROP POLICY IF EXISTS "Users read own favorites" ON public.listing_favorites;
CREATE POLICY "Users read own favorites"
  ON public.listing_favorites
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users add favorites" ON public.listing_favorites;
CREATE POLICY "Users add favorites"
  ON public.listing_favorites
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users remove favorites" ON public.listing_favorites;
CREATE POLICY "Users remove favorites"
  ON public.listing_favorites
  FOR DELETE
  TO authenticated
  USING (user_id = auth.uid());
