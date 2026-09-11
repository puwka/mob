-- Ensure chat-images bucket stays public (recipient loads via public URL)

UPDATE storage.buckets
SET
  public = true,
  file_size_limit = COALESCE(file_size_limit, 8388608),
  allowed_mime_types = COALESCE(
    allowed_mime_types,
    ARRAY['image/jpeg', 'image/png', 'image/webp']
  )
WHERE id = 'chat-images';

DROP POLICY IF EXISTS "Chat images publicly readable" ON storage.objects;
CREATE POLICY "Chat images publicly readable"
  ON storage.objects
  FOR SELECT
  USING (bucket_id = 'chat-images');
