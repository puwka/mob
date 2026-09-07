import { createClient } from "@/lib/supabase/client";

export type StorageBucket =
  | "avatars"
  | "listing-images"
  | "event-images"
  | "clan-images"
  | "achievement-icons";

export async function uploadAdminFile(opts: {
  bucket: StorageBucket;
  path: string;
  file: File;
}): Promise<string> {
  const supabase = createClient();
  const ext = opts.file.name.split(".").pop()?.toLowerCase() || "jpg";
  const objectPath = `${opts.path}.${ext}`.replace(/\.\./g, ".");

  const { error } = await supabase.storage
    .from(opts.bucket)
    .upload(objectPath, opts.file, {
      upsert: true,
      contentType: opts.file.type || "image/jpeg",
      cacheControl: "3600",
    });
  if (error) throw new Error(error.message);

  const { data } = supabase.storage.from(opts.bucket).getPublicUrl(objectPath);
  return `${data.publicUrl}?v=${Date.now()}`;
}
