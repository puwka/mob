"use client";

import { Button } from "@/components/ui/button";
import { uploadAdminFile, type StorageBucket } from "@/lib/storage";
import { useState } from "react";

export function ImageUploadField({
  bucket,
  folder,
  value,
  onChange,
  label = "Изображение",
  hint,
}: {
  bucket: StorageBucket;
  folder: string;
  value?: string | null;
  onChange: (url: string | null) => void;
  label?: string;
  hint?: string;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  return (
    <div className="space-y-2">
      <div className="text-[12px] text-graphite-600">{label}</div>
      {hint ? (
        <p className="text-[11px] leading-snug text-graphite-600">{hint}</p>
      ) : null}
      {value ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={value}
          alt=""
          className="h-24 w-24 rounded object-cover border border-graphite-700"
        />
      ) : null}
      <div className="flex flex-wrap gap-2">
        <label className="admin-btn-ghost cursor-pointer">
          {busy ? "Загрузка…" : "Загрузить"}
          <input
            type="file"
            accept="image/*"
            className="hidden"
            disabled={busy}
            onChange={async (e) => {
              const file = e.target.files?.[0];
              if (!file) return;
              setBusy(true);
              setError(null);
              try {
                const url = await uploadAdminFile({
                  bucket,
                  path: `${folder}/${Date.now()}`,
                  file,
                });
                onChange(url);
              } catch (err) {
                setError(err instanceof Error ? err.message : "Ошибка загрузки");
              } finally {
                setBusy(false);
                e.target.value = "";
              }
            }}
          />
        </label>
        {value ? (
          <Button type="button" variant="ghost" onClick={() => onChange(null)}>
            Убрать
          </Button>
        ) : null}
      </div>
      {error ? <p className="text-[12px] text-red-300">{error}</p> : null}
    </div>
  );
}
