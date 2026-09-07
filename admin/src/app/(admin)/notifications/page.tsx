"use client";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  EmptyState,
  ErrorBlock,
  LoadingBlock,
  PageHeader,
} from "@/components/ui/page";
import { fetchClans, fetchCities } from "@/lib/api/content";
import {
  createNotification,
  fetchNotifications,
} from "@/lib/api/final";
import { formatDate } from "@/lib/utils";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";

const TYPES = [
  { id: "all_users", label: "Все пользователи" },
  { id: "organizers", label: "Организаторы" },
  { id: "city_users", label: "Пользователи города" },
  { id: "event_participants", label: "Участники мероприятия" },
  { id: "clan_members", label: "Участники клана" },
] as const;

export default function NotificationsPage() {
  const qc = useQueryClient();
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [type, setType] = useState<string>("all_users");
  const [city, setCity] = useState("");
  const [clanId, setClanId] = useState("");
  const [msg, setMsg] = useState<string | null>(null);

  const listQ = useQuery({
    queryKey: ["admin-notifications"],
    queryFn: fetchNotifications,
  });
  const citiesQ = useQuery({
    queryKey: ["cities"],
    queryFn: () => fetchCities(),
  });
  const clansQ = useQuery({
    queryKey: ["admin-clans"],
    queryFn: () => fetchClans(),
  });

  const createMut = useMutation({
    mutationFn: () =>
      createNotification({
        title,
        body,
        type,
        targetCity: type === "city_users" ? city : undefined,
        targetClanId: type === "clan_members" ? clanId : undefined,
      }),
    onSuccess: async () => {
      setMsg("Уведомление создано (queued). Push — отдельный сервис.");
      setTitle("");
      setBody("");
      await qc.invalidateQueries({ queryKey: ["admin-notifications"] });
    },
    onError: (e: Error) => setMsg(e.message),
  });

  return (
    <div>
      <PageHeader
        title="Уведомления"
        description="Структура системных уведомлений. Отправка FCM/APNs подключается отдельно."
      />
      {msg ? (
        <div className="mb-3 rounded border border-graphite-700 px-3 py-2 text-sm text-lime">
          {msg}
        </div>
      ) : null}

      <div className="mb-6 grid gap-4 xl:grid-cols-2">
        <div className="admin-card space-y-2 p-4">
          <h2 className="text-sm font-semibold text-white">Создать</h2>
          <input
            className="admin-input"
            placeholder="Название"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
          />
          <textarea
            className="admin-input min-h-[90px]"
            placeholder="Текст"
            value={body}
            onChange={(e) => setBody(e.target.value)}
          />
          <select
            className="admin-input"
            value={type}
            onChange={(e) => setType(e.target.value)}
          >
            {TYPES.map((t) => (
              <option key={t.id} value={t.id}>
                {t.label}
              </option>
            ))}
          </select>
          {type === "city_users" ? (
            <select
              className="admin-input"
              value={city}
              onChange={(e) => setCity(e.target.value)}
            >
              <option value="">Город</option>
              {(citiesQ.data ?? []).map((c) => (
                <option key={c.id} value={c.name}>
                  {c.name}
                </option>
              ))}
            </select>
          ) : null}
          {type === "clan_members" ? (
            <select
              className="admin-input"
              value={clanId}
              onChange={(e) => setClanId(e.target.value)}
            >
              <option value="">Клан</option>
              {(clansQ.data ?? []).map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
          ) : null}
          <Button
            disabled={
              !title.trim() ||
              !body.trim() ||
              createMut.isPending ||
              (type === "city_users" && !city) ||
              (type === "clan_members" && !clanId)
            }
            onClick={() => createMut.mutate()}
          >
            Поставить в очередь
          </Button>
        </div>

        <div>
          {listQ.isLoading ? <LoadingBlock /> : null}
          {listQ.error ? (
            <ErrorBlock message={(listQ.error as Error).message} />
          ) : null}
          {!listQ.isLoading && !(listQ.data?.length) ? (
            <EmptyState message="Уведомлений пока нет" />
          ) : null}
          <div className="space-y-2">
            {(listQ.data ?? []).map((n) => (
              <div key={n.id} className="admin-card p-3">
                <div className="mb-1 flex flex-wrap items-center gap-2">
                  <span className="font-medium text-white">{n.title}</span>
                  <Badge tone="neutral">{n.type}</Badge>
                  <Badge tone={n.status === "queued" ? "amber" : "lime"}>
                    {n.status}
                  </Badge>
                </div>
                <p className="text-sm text-graphite-600">{n.body}</p>
                <div className="mt-1 text-[11px] text-graphite-600">
                  {formatDate(n.created_at)}
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
