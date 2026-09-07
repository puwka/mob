"use client";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { ImageUploadField } from "@/components/ui/image-upload";
import {
  EmptyState,
  ErrorBlock,
  LoadingBlock,
  PageHeader,
} from "@/components/ui/page";
import {
  deleteAchievement,
  fetchAchievements,
  upsertAchievement,
  type AchievementRow,
} from "@/lib/api/content";
import { ACHIEVEMENT_TYPES } from "@/lib/constants";
import { formatNumber } from "@/lib/utils";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";

export default function AchievementsPage() {
  const qc = useQueryClient();
  const [editing, setEditing] = useState<AchievementRow | null | "new">(null);
  const [msg, setMsg] = useState<string | null>(null);

  const listQ = useQuery({
    queryKey: ["admin-achievements"],
    queryFn: fetchAchievements,
  });

  const delMut = useMutation({
    mutationFn: deleteAchievement,
    onSuccess: async () => {
      setMsg("Удалено");
      await qc.invalidateQueries({ queryKey: ["admin-achievements"] });
    },
    onError: (e: Error) => setMsg(e.message),
  });

  return (
    <div>
      <PageHeader
        title="Достижения"
        description="Каталог из БД (мобильное приложение читает отсюда)"
        actions={
          <Button type="button" onClick={() => setEditing("new")}>
            Создать
          </Button>
        }
      />
      {msg ? (
        <div className="mb-3 rounded border border-graphite-700 px-3 py-2 text-sm text-lime">
          {msg}
        </div>
      ) : null}

      {listQ.isLoading ? <LoadingBlock /> : null}
      {listQ.error ? <ErrorBlock message={(listQ.error as Error).message} /> : null}
      {!listQ.isLoading && !(listQ.data?.length) ? (
        <EmptyState message="Нет достижений" />
      ) : null}

      {(listQ.data?.length ?? 0) > 0 ? (
        <div className="admin-table-wrap">
          <table className="admin-table">
            <thead>
              <tr>
                <th>Название</th>
                <th>Тип</th>
                <th>Условие</th>
                <th>Иконка</th>
                <th>Активно</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {listQ.data!.map((a) => (
                <tr key={a.id}>
                  <td>
                    <div className="font-medium text-white">{a.title}</div>
                    <div className="text-[12px] text-graphite-600">
                      {a.description}
                    </div>
                  </td>
                  <td>
                    <Badge tone="neutral">{a.type}</Badge>
                  </td>
                  <td className="font-mono text-[12px]">
                    {a.type} &gt;= {formatNumber(a.required_value)}
                  </td>
                  <td className="text-[12px]">{a.icon}</td>
                  <td>
                    <Badge tone={a.is_active ? "lime" : "red"}>
                      {a.is_active ? "on" : "off"}
                    </Badge>
                  </td>
                  <td>
                    <div className="flex gap-1">
                      <Button
                        variant="ghost"
                        className="h-7 px-2 text-[12px]"
                        onClick={() => setEditing(a)}
                      >
                        Изменить
                      </Button>
                      <Button
                        variant="danger"
                        className="h-7 px-2 text-[12px]"
                        onClick={() => {
                          if (confirm("Удалить достижение?"))
                            delMut.mutate(a.id);
                        }}
                      >
                        Удалить
                      </Button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}

      {editing ? (
        <AchievementForm
          initial={editing === "new" ? null : editing}
          onClose={() => setEditing(null)}
          onSaved={async () => {
            setEditing(null);
            setMsg("Сохранено");
            await qc.invalidateQueries({ queryKey: ["admin-achievements"] });
          }}
        />
      ) : null}
    </div>
  );
}

function AchievementForm({
  initial,
  onClose,
  onSaved,
}: {
  initial: AchievementRow | null;
  onClose: () => void;
  onSaved: () => Promise<void>;
}) {
  const [title, setTitle] = useState(initial?.title ?? "");
  const [description, setDescription] = useState(initial?.description ?? "");
  const [icon, setIcon] = useState(initial?.icon ?? "award");
  const [type, setType] = useState(initial?.type ?? "games_played");
  const [requiredValue, setRequiredValue] = useState(
    initial?.required_value ?? 10,
  );
  const [isActive, setIsActive] = useState(initial?.is_active ?? true);
  const [iconUrl, setIconUrl] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4">
      <div className="w-full max-w-lg rounded-lg border border-graphite-700 bg-graphite-900 p-4">
        <h2 className="mb-3 text-sm font-semibold text-white">
          {initial ? "Редактировать" : "Новое достижение"}
        </h2>
        <div className="space-y-2">
          <input
            className="admin-input"
            placeholder="Название"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
          />
          <textarea
            className="admin-input min-h-[70px]"
            placeholder="Описание"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
          />
          <select
            className="admin-input"
            value={type}
            onChange={(e) => setType(e.target.value)}
          >
            {ACHIEVEMENT_TYPES.map((t) => (
              <option key={t} value={t}>
                {t}
              </option>
            ))}
          </select>
          <input
            className="admin-input"
            type="number"
            min={1}
            value={requiredValue}
            onChange={(e) => setRequiredValue(Number(e.target.value))}
          />
          <input
            className="admin-input"
            placeholder="Ключ иконки (veteran, activist…)"
            value={icon}
            onChange={(e) => setIcon(e.target.value)}
          />
          <ImageUploadField
            bucket="achievement-icons"
            folder="icons"
            value={iconUrl}
            onChange={(url) => {
              setIconUrl(url);
              if (url) setIcon(url);
            }}
            label="Или загрузить файл иконки (URL сохранится в icon)"
          />
          <label className="flex items-center gap-2 text-sm text-white">
            <input
              type="checkbox"
              checked={isActive}
              onChange={(e) => setIsActive(e.target.checked)}
            />
            Активно
          </label>
          {error ? <p className="text-[12px] text-red-300">{error}</p> : null}
          <div className="flex justify-end gap-2">
            <Button variant="ghost" onClick={onClose}>
              Отмена
            </Button>
            <Button
              disabled={busy}
              onClick={async () => {
                setBusy(true);
                setError(null);
                try {
                  await upsertAchievement({
                    id: initial?.id,
                    title,
                    description,
                    icon,
                    type,
                    requiredValue,
                    isActive,
                  });
                  await onSaved();
                } catch (e) {
                  setError(e instanceof Error ? e.message : "Ошибка");
                } finally {
                  setBusy(false);
                }
              }}
            >
              Сохранить
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}
