"use client";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Avatar,
  ErrorBlock,
  LoadingBlock,
  PageHeader,
} from "@/components/ui/page";
import { fetchUsers } from "@/lib/api/admin";
import {
  cancelParticipant,
  confirmParticipant,
  fetchEvents,
  fetchParticipants,
  registerParticipant,
  removeParticipant,
  upsertEvent,
} from "@/lib/api/content";
import { formatDate, formatNumber } from "@/lib/utils";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useMemo, useState } from "react";

export default function EventDetailPage() {
  const { id } = useParams<{ id: string }>();
  const qc = useQueryClient();
  const [msg, setMsg] = useState<string | null>(null);
  const [userQuery, setUserQuery] = useState("");
  const [selectedUser, setSelectedUser] = useState("");

  const eventQ = useQuery({
    queryKey: ["admin-event", id],
    queryFn: async () => {
      const rows = await fetchEvents({ search: undefined, limit: 200 });
      return rows.find((e) => e.id === id) ?? null;
    },
  });

  const partsQ = useQuery({
    queryKey: ["admin-event-parts", id],
    queryFn: () => fetchParticipants(id),
  });

  const usersQ = useQuery({
    queryKey: ["admin-users-pick", userQuery],
    queryFn: () => fetchUsers({ search: userQuery || undefined, limit: 30 }),
    enabled: userQuery.length >= 2,
  });

  const invalidate = async () => {
    await qc.invalidateQueries({ queryKey: ["admin-event-parts", id] });
    await qc.invalidateQueries({ queryKey: ["admin-event", id] });
    await qc.invalidateQueries({ queryKey: ["admin-events"] });
  };

  const mut = useMutation({
    mutationFn: async (fn: () => Promise<unknown>) => fn(),
    onSuccess: async () => {
      setMsg("Готово");
      await invalidate();
    },
    onError: (e: Error) => setMsg(e.message),
  });

  const event = eventQ.data;

  const users = useMemo(() => usersQ.data ?? [], [usersQ.data]);

  if (eventQ.isLoading) return <LoadingBlock />;
  if (!event) return <ErrorBlock message="Мероприятие не найдено" />;

  return (
    <div>
      <PageHeader
        title={event.title}
        description={`${event.city} · ${formatDate(event.event_date)} · лимит ${formatNumber(event.max_participants)}`}
        actions={
          <div className="flex gap-2">
            <Button
              variant="ghost"
              onClick={() =>
                mut.mutate(() =>
                  upsertEvent({ id: event.id, status: "cancelled" }),
                )
              }
            >
              Отменить
            </Button>
            <Link href="/events" className="admin-btn-ghost">
              ← К списку
            </Link>
          </div>
        }
      />

      {msg ? (
        <div className="mb-3 rounded border border-graphite-700 px-3 py-2 text-sm text-lime">
          {msg}
        </div>
      ) : null}

      <div className="mb-4 grid gap-2 sm:grid-cols-4">
        <Stat label="Статус" value={event.status} />
        <Stat label="Организатор" value={event.organizer_nickname ?? "—"} />
        <Stat
          label="Участники"
          value={`${formatNumber(event.participants_count)} / ${formatNumber(event.max_participants)}`}
        />
        <Stat label="Локация" value={event.location} />
      </div>

      <div className="mb-4 admin-card p-4">
        <h2 className="mb-2 text-sm font-semibold text-white">
          Зарегистрировать участника
        </h2>
        <div className="flex flex-wrap gap-2">
          <input
            className="admin-input max-w-xs"
            placeholder="Поиск никнейма…"
            value={userQuery}
            onChange={(e) => setUserQuery(e.target.value)}
          />
          <select
            className="admin-input max-w-xs"
            value={selectedUser}
            onChange={(e) => setSelectedUser(e.target.value)}
          >
            <option value="">Выберите пользователя</option>
            {users.map((u) => (
              <option key={u.id} value={u.id}>
                {u.nickname} · {u.city}
              </option>
            ))}
          </select>
          <Button
            type="button"
            disabled={!selectedUser || mut.isPending}
            onClick={() =>
              mut.mutate(() => registerParticipant(id, selectedUser))
            }
          >
            Зарегистрировать
          </Button>
        </div>
      </div>

      <h2 className="mb-2 text-sm font-semibold text-white">Участники</h2>
      {partsQ.isLoading ? <LoadingBlock /> : null}
      {partsQ.error ? (
        <ErrorBlock message={(partsQ.error as Error).message} />
      ) : null}

      <div className="admin-table-wrap">
        <table className="admin-table">
          <thead>
            <tr>
              <th></th>
              <th>Nickname</th>
              <th>City</th>
              <th>Registration</th>
              <th>Attendance</th>
              <th>Registered</th>
              <th>Attended</th>
              <th>Confirmed by</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {(partsQ.data ?? []).map((p) => (
              <tr key={p.id}>
                <td>
                  <Avatar src={p.avatar_url} name={p.nickname} />
                </td>
                <td>
                  <Link href={`/users/${p.user_id}`} className="text-lime hover:underline">
                    {p.nickname}
                  </Link>
                </td>
                <td>{p.city}</td>
                <td>
                  <Badge
                    tone={
                      p.registration_status === "registered" ? "lime" : "neutral"
                    }
                  >
                    {p.registration_status}
                  </Badge>
                </td>
                <td>
                  <Badge
                    tone={
                      p.attendance_status === "confirmed" ? "blue" : "neutral"
                    }
                  >
                    {p.attendance_status}
                  </Badge>
                </td>
                <td className="text-graphite-600">
                  {formatDate(p.registered_at)}
                </td>
                <td className="text-graphite-600">
                  {formatDate(p.attended_at)}
                </td>
                <td>{p.confirmed_by_nickname ?? "—"}</td>
                <td>
                  <div className="flex flex-wrap gap-1">
                    {p.registration_status === "registered" &&
                    p.attendance_status !== "confirmed" ? (
                      <Button
                        variant="ghost"
                        className="h-7 px-2 text-[12px]"
                        onClick={() =>
                          mut.mutate(() => confirmParticipant(p.id))
                        }
                      >
                        Подтвердить
                      </Button>
                    ) : null}
                    {p.registration_status === "registered" ? (
                      <Button
                        variant="ghost"
                        className="h-7 px-2 text-[12px]"
                        onClick={() =>
                          mut.mutate(() => cancelParticipant(p.id))
                        }
                      >
                        Отменить
                      </Button>
                    ) : null}
                    <Button
                      variant="danger"
                      className="h-7 px-2 text-[12px]"
                      onClick={() => {
                        if (confirm("Удалить участника?")) {
                          mut.mutate(() => removeParticipant(p.id));
                        }
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
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="admin-card px-3 py-2">
      <div className="text-[11px] uppercase tracking-wide text-graphite-600">
        {label}
      </div>
      <div className="mt-0.5 text-sm text-white">{value}</div>
    </div>
  );
}
