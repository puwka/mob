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
import { fetchOrganizers } from "@/lib/api/admin";
import {
  deleteEvent,
  fetchCities,
  fetchEvents,
  upsertEvent,
  type EventRow,
} from "@/lib/api/content";
import { EVENT_STATUSES } from "@/lib/constants";
import { formatDate, formatNumber } from "@/lib/utils";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useMemo, useState } from "react";

export default function EventsPage() {
  const qc = useQueryClient();
  const [search, setSearch] = useState("");
  const [city, setCity] = useState("");
  const [status, setStatus] = useState("");
  const [organizerId, setOrganizerId] = useState("");
  const [dateFrom, setDateFrom] = useState("");
  const [editing, setEditing] = useState<EventRow | null | "new">(null);
  const [msg, setMsg] = useState<string | null>(null);

  const citiesQ = useQuery({ queryKey: ["cities"], queryFn: () => fetchCities() });
  const orgsQ = useQuery({
    queryKey: ["admin-organizers-opts"],
    queryFn: () => fetchOrganizers({ limit: 200 }),
  });

  const params = useMemo(
    () => ({
      search: search.trim() || undefined,
      city: city || undefined,
      status: status || undefined,
      organizerId: organizerId || undefined,
      dateFrom: dateFrom ? new Date(dateFrom).toISOString() : undefined,
    }),
    [search, city, status, organizerId, dateFrom],
  );

  const listQ = useQuery({
    queryKey: ["admin-events", params],
    queryFn: () => fetchEvents(params),
  });

  const delMut = useMutation({
    mutationFn: deleteEvent,
    onSuccess: async () => {
      setMsg("Удалено");
      await qc.invalidateQueries({ queryKey: ["admin-events"] });
    },
    onError: (e: Error) => setMsg(e.message),
  });

  return (
    <div>
      <PageHeader
        title="Мероприятия"
        description="Управление всеми событиями платформы"
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

      <div className="mb-4 grid gap-2 md:grid-cols-3 xl:grid-cols-6">
        <input
          className="admin-input md:col-span-2"
          placeholder="Поиск"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <select className="admin-input" value={city} onChange={(e) => setCity(e.target.value)}>
          <option value="">Город</option>
          {(citiesQ.data ?? []).map((c) => (
            <option key={c.id} value={c.name}>
              {c.name}
            </option>
          ))}
        </select>
        <select
          className="admin-input"
          value={status}
          onChange={(e) => setStatus(e.target.value)}
        >
          <option value="">Статус</option>
          {EVENT_STATUSES.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </select>
        <select
          className="admin-input"
          value={organizerId}
          onChange={(e) => setOrganizerId(e.target.value)}
        >
          <option value="">Организатор</option>
          {(orgsQ.data ?? []).map((o) => (
            <option key={o.id} value={o.id}>
              {o.nickname}
            </option>
          ))}
        </select>
        <input
          className="admin-input"
          type="date"
          value={dateFrom}
          onChange={(e) => setDateFrom(e.target.value)}
        />
      </div>

      {listQ.isLoading ? <LoadingBlock /> : null}
      {listQ.error ? <ErrorBlock message={(listQ.error as Error).message} /> : null}
      {!listQ.isLoading && !(listQ.data?.length) ? (
        <EmptyState message="Мероприятия не найдены" />
      ) : null}

      {(listQ.data?.length ?? 0) > 0 ? (
        <div className="admin-table-wrap">
          <table className="admin-table">
            <thead>
              <tr>
                <th>Название</th>
                <th>Организатор</th>
                <th>Город</th>
                <th>Дата</th>
                <th>Участники</th>
                <th>Лимит</th>
                <th>Статус</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {listQ.data!.map((e) => (
                <tr key={e.id}>
                  <td>
                    <Link
                      href={`/events/${e.id}`}
                      className="font-medium text-lime hover:underline"
                    >
                      {e.title}
                    </Link>
                  </td>
                  <td>{e.organizer_nickname ?? "—"}</td>
                  <td>{e.city}</td>
                  <td className="text-graphite-600">{formatDate(e.event_date)}</td>
                  <td className="tabular-nums">
                    {formatNumber(e.participants_count)}
                  </td>
                  <td className="tabular-nums">
                    {formatNumber(e.max_participants)}
                  </td>
                  <td>
                    <Badge
                      tone={
                        e.status === "active"
                          ? "lime"
                          : e.status === "cancelled"
                            ? "red"
                            : "neutral"
                      }
                    >
                      {e.status}
                    </Badge>
                  </td>
                  <td>
                    <div className="flex gap-1">
                      <Button
                        variant="ghost"
                        className="h-7 px-2 text-[12px]"
                        onClick={() => setEditing(e)}
                      >
                        Изменить
                      </Button>
                      <Button
                        variant="danger"
                        className="h-7 px-2 text-[12px]"
                        onClick={() => {
                          if (confirm("Удалить мероприятие?")) delMut.mutate(e.id);
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
        <EventFormModal
          initial={editing === "new" ? null : editing}
          organizers={orgsQ.data ?? []}
          cities={(citiesQ.data ?? []).map((c) => c.name)}
          onClose={() => setEditing(null)}
          onSaved={async () => {
            setEditing(null);
            setMsg("Сохранено");
            await qc.invalidateQueries({ queryKey: ["admin-events"] });
          }}
        />
      ) : null}
    </div>
  );
}

function EventFormModal({
  initial,
  organizers,
  cities,
  onClose,
  onSaved,
}: {
  initial: EventRow | null;
  organizers: Array<{ id: string; nickname: string }>;
  cities: string[];
  onClose: () => void;
  onSaved: () => Promise<void>;
}) {
  const [title, setTitle] = useState(initial?.title ?? "");
  const [description, setDescription] = useState(initial?.description ?? "");
  const [city, setCity] = useState(initial?.city ?? cities[0] ?? "Москва");
  const [location, setLocation] = useState(initial?.location ?? "");
  const [eventDate, setEventDate] = useState(
    initial?.event_date
      ? initial.event_date.slice(0, 16)
      : new Date().toISOString().slice(0, 16),
  );
  const [organizerId, setOrganizerId] = useState(
    initial?.organizer_id ?? organizers[0]?.id ?? "",
  );
  const [maxParticipants, setMaxParticipants] = useState(
    initial?.max_participants ?? 20,
  );
  const [status, setStatus] = useState(initial?.status ?? "active");
  const [imageUrl, setImageUrl] = useState<string | null>(
    initial?.image_url ?? null,
  );
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4">
      <div className="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-lg border border-graphite-700 bg-graphite-900 p-4 shadow-panel">
        <h2 className="mb-3 text-sm font-semibold text-white">
          {initial ? "Редактировать мероприятие" : "Новое мероприятие"}
        </h2>
        <div className="space-y-2">
          <input
            className="admin-input"
            placeholder="Название"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
          />
          <textarea
            className="admin-input min-h-[80px]"
            placeholder="Описание"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
          />
          <select
            className="admin-input"
            value={city}
            onChange={(e) => setCity(e.target.value)}
          >
            {cities.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
          <input
            className="admin-input"
            placeholder="Локация"
            value={location}
            onChange={(e) => setLocation(e.target.value)}
          />
          <input
            className="admin-input"
            type="datetime-local"
            value={eventDate}
            onChange={(e) => setEventDate(e.target.value)}
          />
          <select
            className="admin-input"
            value={organizerId}
            onChange={(e) => setOrganizerId(e.target.value)}
          >
            {organizers.map((o) => (
              <option key={o.id} value={o.id}>
                {o.nickname}
              </option>
            ))}
          </select>
          <input
            className="admin-input"
            type="number"
            min={1}
            value={maxParticipants}
            onChange={(e) => setMaxParticipants(Number(e.target.value))}
          />
          <select
            className="admin-input"
            value={status}
            onChange={(e) => setStatus(e.target.value)}
          >
            {EVENT_STATUSES.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </select>
          <ImageUploadField
            bucket="event-images"
            folder={organizerId || "admin"}
            value={imageUrl}
            onChange={setImageUrl}
            label="Фото"
          />
          {error ? <p className="text-[12px] text-red-300">{error}</p> : null}
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="ghost" type="button" onClick={onClose}>
              Отмена
            </Button>
            <Button
              type="button"
              disabled={busy}
              onClick={async () => {
                setBusy(true);
                setError(null);
                try {
                  await upsertEvent({
                    id: initial?.id,
                    title,
                    description,
                    city,
                    location,
                    eventDate: new Date(eventDate).toISOString(),
                    organizerId,
                    maxParticipants,
                    status,
                    imageUrl,
                    clearImage: !imageUrl,
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
