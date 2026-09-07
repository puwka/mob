"use client";

import { Button } from "@/components/ui/button";
import {
  EmptyState,
  ErrorBlock,
  LoadingBlock,
  PageHeader,
} from "@/components/ui/page";
import { fetchSettings, upsertSetting } from "@/lib/api/final";
import { usePermissions } from "@/hooks/use-permissions";
import { formatDate } from "@/lib/utils";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";

const LABELS: Record<string, string> = {
  organizer_attendance_reward: "Награда за QR (CR)",
  event_creation_fee: "Комиссия создания события",
  withdrawal_fee: "Комиссия вывода",
  profile_photos_limit: "Лимит фото профиля",
  listing_images_limit: "Лимит фото объявления",
  message_max_length: "Макс. длина сообщения",
  listing_default_status: "Статус объявления по умолчанию",
  moderation_required: "Модерация объявлений обязательна",
  event_default_max_participants: "Лимит участников по умолчанию",
};

export default function SettingsPage() {
  const { can } = usePermissions();
  const qc = useQueryClient();
  const [draft, setDraft] = useState<Record<string, string>>({});
  const [msg, setMsg] = useState<string | null>(null);
  const [newKey, setNewKey] = useState("");
  const [newValue, setNewValue] = useState("");

  const listQ = useQuery({
    queryKey: ["admin-settings"],
    queryFn: fetchSettings,
  });

  useEffect(() => {
    if (!listQ.data) return;
    const next: Record<string, string> = {};
    for (const row of listQ.data) next[row.key] = row.value;
    setDraft(next);
  }, [listQ.data]);

  const saveMut = useMutation({
    mutationFn: ({ key, value }: { key: string; value: string }) =>
      upsertSetting(key, value),
    onSuccess: async () => {
      setMsg("Сохранено в app_settings");
      await qc.invalidateQueries({ queryKey: ["admin-settings"] });
      await qc.invalidateQueries({ queryKey: ["admin-audit-logs"] });
    },
    onError: (e: Error) => setMsg(e.message),
  });

  const canWrite = can("settings_write");

  return (
    <div>
      <PageHeader
        title="Настройки"
        description="Системные параметры в app_settings. Изменение reward не требует релиза приложения."
      />
      {msg ? (
        <div className="mb-3 rounded border border-graphite-700 px-3 py-2 text-sm text-lime">
          {msg}
        </div>
      ) : null}
      {!canWrite ? (
        <div className="mb-3 rounded border border-amber-900/40 bg-amber-950/20 px-3 py-2 text-[12px] text-amber-200">
          Редактирование доступно только Super Admin. Сейчас режим просмотра.
        </div>
      ) : null}

      {listQ.isLoading ? <LoadingBlock /> : null}
      {listQ.error ? <ErrorBlock message={(listQ.error as Error).message} /> : null}
      {!listQ.isLoading && !(listQ.data?.length) ? (
        <EmptyState message="Настройки не найдены — примените миграцию" />
      ) : null}

      <div className="space-y-3">
        {(listQ.data ?? []).map((row) => (
          <div key={row.key} className="admin-card p-4">
            <div className="mb-1 flex flex-wrap items-center justify-between gap-2">
              <div>
                <div className="text-sm font-medium text-white">
                  {LABELS[row.key] ?? row.key}
                </div>
                <div className="font-mono text-[11px] text-graphite-600">
                  {row.key} · обновлено {formatDate(row.updated_at)}
                </div>
              </div>
              {canWrite ? (
                <Button
                  className="h-8"
                  disabled={saveMut.isPending}
                  onClick={() =>
                    saveMut.mutate({
                      key: row.key,
                      value: draft[row.key] ?? row.value,
                    })
                  }
                >
                  Сохранить
                </Button>
              ) : null}
            </div>
            <input
              className="admin-input mt-2"
              value={draft[row.key] ?? ""}
              disabled={!canWrite}
              onChange={(e) =>
                setDraft((d) => ({ ...d, [row.key]: e.target.value }))
              }
            />
          </div>
        ))}
      </div>

      {canWrite ? (
        <div className="mt-6 admin-card space-y-2 p-4">
          <h3 className="text-sm font-semibold text-white">Добавить ключ</h3>
          <input
            className="admin-input"
            placeholder="key"
            value={newKey}
            onChange={(e) => setNewKey(e.target.value)}
          />
          <input
            className="admin-input"
            placeholder="value"
            value={newValue}
            onChange={(e) => setNewValue(e.target.value)}
          />
          <Button
            disabled={!newKey.trim() || saveMut.isPending}
            onClick={() =>
              saveMut.mutate(
                { key: newKey.trim(), value: newValue },
                {
                  onSuccess: () => {
                    setNewKey("");
                    setNewValue("");
                  },
                },
              )
            }
          >
            Создать / обновить
          </Button>
        </div>
      ) : null}
    </div>
  );
}
